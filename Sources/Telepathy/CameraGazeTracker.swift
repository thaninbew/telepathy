import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import Vision

final class CameraGazeTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  enum State: Equatable {
    case stopped
    case requestingPermission
    case running
    case denied
    case unavailable(String)
  }

  var onFeatures: ((GazeFeatures) -> Void)?
  var onStateChange: ((State) -> Void)?

  private let session = AVCaptureSession()
  private let captureQueue = DispatchQueue(label: "app.telepathy.camera", qos: .userInteractive)
  private let visionHandler = VNSequenceRequestHandler()
  private var lastProcessedAt: TimeInterval = 0
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
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureAndStart()
    case .notDetermined:
      state = .requestingPermission
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        guard let self else { return }
        if granted {
          self.configureAndStart()
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
    captureQueue.async { [weak self] in
      self?.session.stopRunning()
      self?.state = .stopped
    }
  }

  private func configureAndStart() {
    captureQueue.async { [weak self] in
      guard let self else { return }
      do {
        if !self.configured {
          try self.configureSession()
          self.configured = true
        }
        guard !self.session.isRunning else { return }
        self.session.startRunning()
        self.state = .running
      } catch {
        self.state = .unavailable(error.localizedDescription)
      }
    }
  }

  private func configureSession() throws {
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    session.sessionPreset = .vga640x480

    guard let device = AVCaptureDevice.default(for: .video) else {
      throw TrackerError.noCamera
    }
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
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastProcessedAt >= 1.0 / 20.0,
      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    else {
      return
    }
    lastProcessedAt = now

    let request = VNDetectFaceLandmarksRequest()
    do {
      try visionHandler.perform([request], on: pixelBuffer, orientation: .up)
      guard let face = request.results?.max(by: { $0.confidence < $1.confidence }),
        let features = extractFeatures(from: face, timestamp: now)
      else {
        return
      }
      DispatchQueue.main.async { [weak self] in
        self?.onFeatures?(features)
      }
    } catch {
      // A dropped Vision frame is transient. The next camera frame retries.
    }
  }

  private func extractFeatures(from face: VNFaceObservation, timestamp: TimeInterval)
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

    var features = GazeFeatures(
      timestamp: timestamp,
      faceX: Double(face.boundingBox.midX),
      faceY: Double(face.boundingBox.midY),
      yaw: face.yaw?.doubleValue ?? 0,
      pitch: face.pitch?.doubleValue ?? 0,
      pupilX: pupilX.isEmpty ? 0.5 : Double(pupilX.reduce(0, +) / CGFloat(pupilX.count)),
      pupilY: pupilY.isEmpty ? 0.5 : Double(pupilY.reduce(0, +) / CGFloat(pupilY.count)),
      confidence: Double(face.confidence)
    )
    features.leftEyeOpenness = apertureRatio(leftEye.normalizedPoints)
    features.rightEyeOpenness = apertureRatio(rightEye.normalizedPoints)
    features.mouthOpenness = landmarks.innerLips.flatMap {
      apertureRatio($0.normalizedPoints)
    }
    return features
  }

  private func apertureRatio(_ points: [CGPoint]) -> Double? {
    guard let minX = points.map(\.x).min(),
      let maxX = points.map(\.x).max(),
      let minY = points.map(\.y).min(),
      let maxY = points.map(\.y).max(),
      maxX - minX > 0.001
    else {
      return nil
    }
    return Double((maxY - minY) / (maxX - minX))
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
