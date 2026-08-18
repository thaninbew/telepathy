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
