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
  private var ready = false

  var isReady: Bool {
    ready
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

    let rawPoints: [TrainingPoint] = samples.compactMap { sample -> TrainingPoint? in
      let point = CGPoint(
        x: desktopBounds.minX + sample.normalizedX * desktopBounds.width,
        y: desktopBounds.minY + sample.normalizedY * desktopBounds.height
      )
      guard let display = DesktopGeometry.display(containing: point, in: displays) else {
        return nil
      }
      return TrainingPoint(displayID: display.id, vector: sample.features.headVector)
    }

    guard !rawPoints.isEmpty else {
      reset()
      return
    }

    let dimension = rawPoints[0].vector.count
    means = Array(repeating: 0, count: dimension)
    for point in rawPoints {
      for index in 0..<dimension {
        means[index] += point.vector[index]
      }
    }
    for index in 0..<dimension {
      means[index] /= Double(rawPoints.count)
    }

    var variances = Array(repeating: 0.0, count: dimension)
    for point in rawPoints {
      for index in 0..<dimension {
        let delta = point.vector[index] - means[index]
        variances[index] += delta * delta
      }
    }
    scales = variances.map {
      max(sqrt($0 / Double(rawPoints.count)), 0.025)
    }
    points = rawPoints.map {
      TrainingPoint(displayID: $0.displayID, vector: standardized($0.vector))
    }
    ready = requiredDisplayIDs.count >= 2 && Set(points.map(\.displayID)) == requiredDisplayIDs
  }

  func predict(features: GazeFeatures) -> DisplayPrediction? {
    guard isReady, means.count == features.headVector.count else { return nil }
    let query = standardized(features.headVector)
    let neighborCount = min(5, points.count)
    var neighbors: [(displayID: CGDirectDisplayID, distance: Double)] = []
    neighbors.reserveCapacity(neighborCount)
    for point in points {
      let candidate = (point.displayID, squaredDistance(query, point.vector))
      if neighbors.count < neighborCount {
        neighbors.append(candidate)
      } else if let worstIndex = neighbors.indices.max(by: {
        neighbors[$0].distance < neighbors[$1].distance
      }), candidate.1 < neighbors[worstIndex].distance {
        neighbors[worstIndex] = candidate
      }
    }

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
    ready = false
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
