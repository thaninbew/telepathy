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

  var vector: [Double] {
    [1, faceX, faceY, yaw, pitch, pupilX, pupilY]
  }
}

enum ActivationMode: String, CaseIterable, Codable {
  case automatic
  case hold
  case keyboard
  case mouse

  func title(shortcutName: String) -> String {
    switch self {
    case .automatic: "Automatic"
    case .hold: "Dwell (650 ms)"
    case .keyboard: "Keyboard (\(shortcutName))"
    case .mouse: "Middle mouse button"
    }
  }

  func detail(shortcutName: String) -> String {
    switch self {
    case .automatic: "Switch after the configured delay."
    case .hold: "Dwell on a display for 650 ms. No key or click required."
    case .keyboard: "Face a display, then press or hold \(shortcutName). Change it below."
    case .mouse: "Face a screen, then press the middle mouse button."
    }
  }
}

struct ShortcutBinding: Codable, Equatable {
  let keyCode: Int64
  let displayName: String

  static let defaultValue = ShortcutBinding(keyCode: 56, displayName: "Left Shift")
  static let legacyRightShiftDefault = ShortcutBinding(keyCode: 60, displayName: "Right Shift")
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
