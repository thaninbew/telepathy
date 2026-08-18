import CoreGraphics
import Foundation

struct GazeFeatures: Equatable, Codable {
  static let dimension = 7

  let timestamp: TimeInterval
  let faceX: Double
  let faceY: Double
  let yaw: Double
  let pitch: Double
  let pupilX: Double
  let pupilY: Double
  let confidence: Double
  var leftEyeOpenness: Double? = nil
  var rightEyeOpenness: Double? = nil
  var mouthOpenness: Double? = nil

  var vector: [Double] {
    [1, faceX, faceY, yaw, pitch, pupilX, pupilY]
  }
}

enum ActivationMode: String, CaseIterable, Codable {
  case automatic
  case hold
  case wink
  case mouthOpen
  case keyboard
  case mouse

  var title: String {
    switch self {
    case .automatic: "Automatic"
    case .hold: "Hold"
    case .wink: "Wink"
    case .mouthOpen: "Mouth open"
    case .keyboard: "Keyboard shortcut"
    case .mouse: "Middle mouse button"
    }
  }

  var detail: String {
    switch self {
    case .automatic: "Switch after a short, stable head turn."
    case .hold: "Keep looking until the screen bloom completes."
    case .wink: "Glance at a screen, then wink to confirm."
    case .mouthOpen: "Glance at a screen, then open your mouth to confirm."
    case .keyboard: "Glance at a screen, then press Command-Option-Space."
    case .mouse: "Glance at a screen, then press the middle mouse button."
    }
  }
}

struct GazePrediction: Equatable {
  let rawPoint: CGPoint
  let smoothedPoint: CGPoint
  let confidence: Double
  let sampleCount: Int
}

struct CalibrationSample: Codable, Equatable {
  let features: GazeFeatures
  let normalizedX: Double
  let normalizedY: Double
}

struct TargetWindow: Equatable {
  let processIdentifier: pid_t
  let frame: CGRect
  let title: String
  let identity: String
}
