import CoreGraphics
import Foundation

struct DisplayPrediction: Equatable {
  let displayID: CGDirectDisplayID
  let confidence: Double
}

final class HeadDisplayClassifier {
  private struct TrainingPoint {
    let displayID: CGDirectDisplayID
    let vector: [Double]
  }

  private var points: [TrainingPoint] = []
  private var means: [Double] = []
  private var scales: [Double] = []
  private var requiredDisplayIDs: Set<CGDirectDisplayID> = []

  var isReady: Bool {
    requiredDisplayIDs.count >= 2 && Set(points.map(\.displayID)) == requiredDisplayIDs
  }

  func fit(
    samples: [CalibrationSample],
    desktopBounds: CGRect,
    displays: [ActiveDisplay]
  ) {
    requiredDisplayIDs = Set(displays.map(\.id))
    guard desktopBounds.width > 0, desktopBounds.height > 0 else {
      reset()
      return
    }

    points = samples.compactMap { sample in
      let point = CGPoint(
        x: desktopBounds.minX + sample.normalizedX * desktopBounds.width,
        y: desktopBounds.minY + sample.normalizedY * desktopBounds.height
      )
      guard let display = DesktopGeometry.display(containing: point, in: displays) else {
        return nil
      }
      return TrainingPoint(displayID: display.id, vector: sample.features.headVector)
    }

    guard !points.isEmpty else {
      reset()
      return
    }

    let dimension = points[0].vector.count
    means = (0..<dimension).map { index in
      points.map { $0.vector[index] }.reduce(0, +) / Double(points.count)
    }
    scales = (0..<dimension).map { index in
      let variance = points.map { value in
        let delta = value.vector[index] - means[index]
        return delta * delta
      }.reduce(0, +) / Double(points.count)
      return max(sqrt(variance), 0.025)
    }
  }

  func predict(features: GazeFeatures) -> DisplayPrediction? {
    guard isReady, means.count == features.headVector.count else { return nil }
    let query = standardized(features.headVector)
    let neighbors = points
      .map { point in
        (point.displayID, squaredDistance(query, standardized(point.vector)))
      }
      .sorted { $0.1 < $1.1 }
      .prefix(min(5, points.count))

    var votes: [CGDirectDisplayID: Double] = [:]
    for (displayID, distance) in neighbors {
      votes[displayID, default: 0] += 1 / max(distance, 0.0001)
    }
    guard let winner = votes.max(by: { $0.value < $1.value }) else { return nil }
    let total = votes.values.reduce(0, +)
    return DisplayPrediction(
      displayID: winner.key,
      confidence: total > 0 ? winner.value / total : 0
    )
  }

  func reset() {
    points = []
    means = []
    scales = []
    requiredDisplayIDs = []
  }

  private func standardized(_ vector: [Double]) -> [Double] {
    zip(zip(vector, means), scales).map { values, scale in
      (values.0 - values.1) / scale
    }
  }

  private func squaredDistance(_ lhs: [Double], _ rhs: [Double]) -> Double {
    zip(lhs, rhs).reduce(0) { result, pair in
      let delta = pair.0 - pair.1
      return result + delta * delta
    }
  }
}

extension GazeFeatures {
  fileprivate var headVector: [Double] {
    [faceX, faceY, yaw, pitch]
  }
}
