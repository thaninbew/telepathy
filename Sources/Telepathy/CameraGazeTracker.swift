import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import Vision

final class CameraGazeTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  enum ProcessingDetail: Equatable, Sendable {
    case headOnly
    case detailed
  }

  enum State: Equatable {
    case stopped
    case requestingPermission
    case running
    case denied
    case unavailable(String)
  }

  var onFeatures: ((GazeFeatures) -> Void)?
  var onStateChange: ((State) -> Void)?

  var processingDetail: ProcessingDetail {
    get { detailLock.withLock { storedProcessingDetail } }
    set {
      let changed = detailLock.withLock {
        guard storedProcessingDetail != newValue else { return false }
        storedProcessingDetail = newValue
        return true
      }
      guard changed else { return }
      captureQueue.async { [weak self] in
        guard let self else { return }
        self.frameCadence.reset()
        self.applyCaptureFrameRate(for: newValue)
      }
    }
  }

  private let session = AVCaptureSession()
  private let captureQueue = DispatchQueue(
    label: "app.telepathy.camera",
    qos: .userInitiated,
    autoreleaseFrequency: .workItem
  )
  private let visionHandler = VNSequenceRequestHandler()
  private let faceRectangleRequest = VNDetectFaceRectanglesRequest()
  private let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
  private let detailLock = NSLock()
  private let lifecycleLock = NSLock()
  private var storedProcessingDetail: ProcessingDetail = .headOnly
  private var lifecycleIntent = CameraLifecycleIntent()
  private var frameCadence = CameraFrameCadence()
  private var captureDevice: AVCaptureDevice?
  private var configured = false

  private(set) var state: State = .stopped {
    didSet {
      guard oldValue != state else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.onStateChange?(self.state)
      }
    }
  }

  func start() {
    let token = lifecycleLock.withLock { lifecycleIntent.requestStart() }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureAndStart(token: token)
    case .notDetermined:
      state = .requestingPermission
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        guard let self else { return }
        guard self.lifecycleLock.withLock({ self.lifecycleIntent.permitsStart(token) }) else {
          return
        }
        if granted {
          self.configureAndStart(token: token)
        } else {
          self.state = .denied
        }
      }
    case .denied, .restricted:
      state = .denied
    @unknown default:
      state = .unavailable("Unknown camera authorization state")
    }
  }

  func stop() {
    let token = lifecycleLock.withLock { lifecycleIntent.requestStop() }
    captureQueue.async { [weak self] in
      guard let self,
        self.lifecycleLock.withLock({ self.lifecycleIntent.permitsStop(token) })
      else { return }
      self.session.stopRunning()
      self.state = .stopped
    }
  }

  private func configureAndStart(token: CameraLifecycleIntent.Token) {
    captureQueue.async { [weak self] in
      guard let self,
        self.lifecycleLock.withLock({ self.lifecycleIntent.permitsStart(token) })
      else { return }
      do {
        if !self.configured {
          try self.configureSession()
          self.configured = true
        }
        guard !self.session.isRunning else { return }
        self.frameCadence.reset()
        self.session.startRunning()
        self.state = .running
      } catch {
        self.state = .unavailable(error.localizedDescription)
      }
    }
  }

  private func configureSession() throws {
    session.beginConfiguration()
    do {
      session.sessionPreset = .vga640x480

      guard let device = AVCaptureDevice.default(for: .video) else {
        throw TrackerError.noCamera
      }
      captureDevice = device
      let input = try AVCaptureDeviceInput(device: device)
      guard session.canAddInput(input) else { throw TrackerError.cannotAddInput }
      session.addInput(input)

      let output = AVCaptureVideoDataOutput()
      output.alwaysDiscardsLateVideoFrames = true
      output.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
      ]
      output.setSampleBufferDelegate(self, queue: captureQueue)
      guard session.canAddOutput(output) else { throw TrackerError.cannotAddOutput }
      session.addOutput(output)

      if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
      }
      session.commitConfiguration()
    } catch {
      session.commitConfiguration()
      throw error
    }

    applyCaptureFrameRate(for: processingDetail)
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let now = ProcessInfo.processInfo.systemUptime
    let detail = processingDetail
    guard frameCadence.shouldProcess(at: now, detail: detail),
      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    else { return }

    do {
      let features: GazeFeatures?
      switch detail {
      case .headOnly:
        try visionHandler.perform([faceRectangleRequest], on: pixelBuffer, orientation: .up)
        features = faceRectangleRequest.results?
          .max(by: { $0.confidence < $1.confidence })
          .map { extractHeadFeatures(from: $0, timestamp: now) }
      case .detailed:
        try visionHandler.perform([faceLandmarksRequest], on: pixelBuffer, orientation: .up)
        features = faceLandmarksRequest.results?
          .max(by: { $0.confidence < $1.confidence })
          .flatMap { extractDetailedFeatures(from: $0, timestamp: now) }
      }
      guard let features else { return }
      DispatchQueue.main.async { [weak self] in
        self?.onFeatures?(features)
      }
    } catch {
      // A dropped Vision frame is transient. The next camera frame retries.
    }
  }

  private func extractHeadFeatures(from face: VNFaceObservation, timestamp: TimeInterval)
    -> GazeFeatures
  {
    GazeFeatures(
      timestamp: timestamp,
      faceX: Double(face.boundingBox.midX),
      faceY: Double(face.boundingBox.midY),
      yaw: face.yaw?.doubleValue ?? 0,
      pitch: face.pitch?.doubleValue ?? 0,
      pupilX: 0.5,
      pupilY: 0.5,
      confidence: Double(face.confidence)
    )
  }

  private func extractDetailedFeatures(from face: VNFaceObservation, timestamp: TimeInterval)
    -> GazeFeatures?
  {
    guard let landmarks = face.landmarks,
      let leftEye = landmarks.leftEye,
      let rightEye = landmarks.rightEye
    else {
      return nil
    }

    let leftRelative = landmarks.leftPupil?.normalizedPoints.first.flatMap {
      relativePupil($0, in: leftEye.normalizedPoints)
    }
    let rightRelative = landmarks.rightPupil?.normalizedPoints.first.flatMap {
      relativePupil($0, in: rightEye.normalizedPoints)
    }
    let pupilX = [leftRelative?.x, rightRelative?.x].compactMap { $0 }
    let pupilY = [leftRelative?.y, rightRelative?.y].compactMap { $0 }

    return GazeFeatures(
      timestamp: timestamp,
      faceX: Double(face.boundingBox.midX),
      faceY: Double(face.boundingBox.midY),
      yaw: face.yaw?.doubleValue ?? 0,
      pitch: face.pitch?.doubleValue ?? 0,
      pupilX: pupilX.isEmpty ? 0.5 : Double(pupilX.reduce(0, +) / CGFloat(pupilX.count)),
      pupilY: pupilY.isEmpty ? 0.5 : Double(pupilY.reduce(0, +) / CGFloat(pupilY.count)),
      confidence: Double(face.confidence)
    )
  }

  private func relativePupil(_ pupil: CGPoint, in eyePoints: [CGPoint]) -> CGPoint? {
    guard let minX = eyePoints.map(\.x).min(),
      let maxX = eyePoints.map(\.x).max(),
      let minY = eyePoints.map(\.y).min(),
      let maxY = eyePoints.map(\.y).max(),
      maxX - minX > 0.001,
      maxY - minY > 0.001
    else {
      return nil
    }
    return CGPoint(
      x: (pupil.x - minX) / (maxX - minX),
      y: (pupil.y - minY) / (maxY - minY)
    )
  }

  private func applyCaptureFrameRate(for detail: ProcessingDetail) {
    guard let captureDevice else { return }
    let ranges = captureDevice.activeFormat.videoSupportedFrameRateRanges.map {
      CameraFrameRateRange(minimum: $0.minFrameRate, maximum: $0.maxFrameRate)
    }
    guard
      let framesPerSecond = CameraFrameRatePolicy.supportedFramesPerSecond(
        for: detail,
        ranges: ranges
      )
    else { return }

    do {
      try captureDevice.lockForConfiguration()
      defer { captureDevice.unlockForConfiguration() }
      let duration = CMTime(seconds: 1 / framesPerSecond, preferredTimescale: 60_000)
      if CMTimeCompare(duration, captureDevice.activeVideoMaxFrameDuration) > 0 {
        captureDevice.activeVideoMaxFrameDuration = duration
        captureDevice.activeVideoMinFrameDuration = duration
      } else {
        captureDevice.activeVideoMinFrameDuration = duration
        captureDevice.activeVideoMaxFrameDuration = duration
      }
    } catch {
      // Some cameras do not permit runtime frame-duration changes. The software
      // cadence gate still bounds Vision processing when configuration is unavailable.
    }
  }
}

struct CameraFrameRateRange: Equatable, Sendable {
  let minimum: Double
  let maximum: Double
}

enum CameraFrameRatePolicy {
  static func targetFramesPerSecond(for detail: CameraGazeTracker.ProcessingDetail) -> Double {
    switch detail {
    case .headOnly: 15
    case .detailed: 20
    }
  }

  static func supportedFramesPerSecond(
    for detail: CameraGazeTracker.ProcessingDetail,
    ranges: [CameraFrameRateRange]
  ) -> Double? {
    let target = targetFramesPerSecond(for: detail)
    let validRanges = ranges.filter {
      $0.minimum.isFinite && $0.maximum.isFinite && $0.minimum > 0 && $0.maximum >= $0.minimum
    }
    guard !validRanges.isEmpty else { return nil }
    if validRanges.contains(where: { $0.minimum <= target && target <= $0.maximum }) {
      return target
    }

    return
      validRanges
      .flatMap { [$0.minimum, $0.maximum] }
      .min { left, right in
        let leftDistance = abs(left - target)
        let rightDistance = abs(right - target)
        return leftDistance == rightDistance ? left < right : leftDistance < rightDistance
      }
  }
}

struct CameraFrameCadence: Equatable, Sendable {
  private(set) var nextFrameAt: TimeInterval?

  mutating func reset() {
    nextFrameAt = nil
  }

  mutating func shouldProcess(
    at timestamp: TimeInterval,
    detail: CameraGazeTracker.ProcessingDetail
  ) -> Bool {
    let interval = 1 / CameraFrameRatePolicy.targetFramesPerSecond(for: detail)
    guard let deadline = nextFrameAt else {
      nextFrameAt = timestamp + interval
      return true
    }
    guard timestamp >= deadline else { return false }

    var nextDeadline = deadline + interval
    while nextDeadline <= timestamp {
      nextDeadline += interval
    }
    nextFrameAt = nextDeadline
    return true
  }
}

struct CameraLifecycleIntent: Equatable, Sendable {
  typealias Token = UInt64

  private(set) var generation: Token = 0
  private(set) var wantsRunning = false

  mutating func requestStart() -> Token {
    update(wantsRunning: true)
  }

  mutating func requestStop() -> Token {
    update(wantsRunning: false)
  }

  func permitsStart(_ token: Token) -> Bool {
    generation == token && wantsRunning
  }

  func permitsStop(_ token: Token) -> Bool {
    generation == token && !wantsRunning
  }

  private mutating func update(wantsRunning: Bool) -> Token {
    generation &+= 1
    self.wantsRunning = wantsRunning
    return generation
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}

private enum TrackerError: LocalizedError {
  case noCamera
  case cannotAddInput
  case cannotAddOutput

  var errorDescription: String? {
    switch self {
    case .noCamera: "No camera is available."
    case .cannotAddInput: "The camera input could not be attached."
    case .cannotAddOutput: "The camera video output could not be attached."
    }
  }
}
