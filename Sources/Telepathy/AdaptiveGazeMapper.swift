import CoreGraphics
import Foundation

final class AdaptiveGazeMapper {
  static let minimumSampleCount = 10
  static let maximumSampleCount = 120

  private(set) var samples: [CalibrationSample] = []
  private(set) var xWeights: [Double]?
  private(set) var yWeights: [Double]?

  var sampleCount: Int { samples.count }
  var isReady: Bool { xWeights != nil && yWeights != nil }

  func addSample(features: GazeFeatures, point: CGPoint, desktopBounds: CGRect) {
    guard
      let sample = Self.makeSample(
        features: features,
        point: point,
        desktopBounds: desktopBounds
      )
    else { return }

    if let last = samples.last {
      let dx = last.normalizedX - sample.normalizedX
      let dy = last.normalizedY - sample.normalizedY
      let featureDelta = zip(last.features.vector, features.vector)
        .map { abs($0 - $1) }
        .reduce(0, +)
      if hypot(dx, dy) < 0.015 && featureDelta < 0.02 {
        return
      }
    }

    samples.append(sample)
    if samples.count > Self.maximumSampleCount {
      samples.removeFirst(samples.count - Self.maximumSampleCount)
    }
    refit()
  }

  static func makeSample(
    features: GazeFeatures,
    point: CGPoint,
    desktopBounds: CGRect
  ) -> CalibrationSample? {
    guard desktopBounds.width > 0, desktopBounds.height > 0 else { return nil }

    let normalizedX = Double((point.x - desktopBounds.minX) / desktopBounds.width)
    let normalizedY = Double((point.y - desktopBounds.minY) / desktopBounds.height)
    guard normalizedX.isFinite, normalizedY.isFinite else { return nil }

    return CalibrationSample(
      features: features,
      normalizedX: normalizedX,
      normalizedY: normalizedY
    )
  }

  func predict(features: GazeFeatures, desktopBounds: CGRect) -> CGPoint? {
    guard let xWeights, let yWeights,
      xWeights.count == GazeFeatures.dimension,
      yWeights.count == GazeFeatures.dimension
    else {
      return nil
    }

    let vector = features.vector
    let normalizedX = dot(vector, xWeights).clamped(to: 0...1)
    let normalizedY = dot(vector, yWeights).clamped(to: 0...1)
    return CGPoint(
      x: desktopBounds.minX + normalizedX * desktopBounds.width,
      y: desktopBounds.minY + normalizedY * desktopBounds.height
    )
  }

  func reset() {
    samples.removeAll()
    xWeights = nil
    yWeights = nil
  }

  func restore(samples restoredSamples: [CalibrationSample]) {
    samples = Array(restoredSamples.suffix(Self.maximumSampleCount))
    refit()
  }

  private func refit() {
    guard samples.count >= Self.minimumSampleCount,
      hasUsefulCoverage(samples)
    else {
      xWeights = nil
      yWeights = nil
      return
    }

    let rows = samples.map(\.features.vector)
    xWeights = solveRidge(rows: rows, values: samples.map(\.normalizedX), lambda: 0.008)
    yWeights = solveRidge(rows: rows, values: samples.map(\.normalizedY), lambda: 0.008)
  }

  private func hasUsefulCoverage(_ samples: [CalibrationSample]) -> Bool {
    guard let minX = samples.map(\.normalizedX).min(),
      let maxX = samples.map(\.normalizedX).max(),
      let minY = samples.map(\.normalizedY).min(),
      let maxY = samples.map(\.normalizedY).max()
    else {
      return false
    }
    return maxX - minX >= 0.18 && maxY - minY >= 0.12
  }

  private func solveRidge(rows: [[Double]], values: [Double], lambda: Double) -> [Double]? {
    let dimension = GazeFeatures.dimension
    guard rows.count == values.count, rows.allSatisfy({ $0.count == dimension }) else {
      return nil
    }

    var matrix = Array(repeating: Array(repeating: 0.0, count: dimension), count: dimension)
    var vector = Array(repeating: 0.0, count: dimension)

    for (row, value) in zip(rows, values) {
      for i in 0..<dimension {
        vector[i] += row[i] * value
        for j in 0..<dimension {
          matrix[i][j] += row[i] * row[j]
        }
      }
    }

    for i in 1..<dimension {
      matrix[i][i] += lambda
    }

    return gaussianElimination(matrix: matrix, vector: vector)
  }

  private func gaussianElimination(matrix: [[Double]], vector: [Double]) -> [Double]? {
    var augmented = zip(matrix, vector).map { row, value in row + [value] }
    let count = augmented.count

    for pivot in 0..<count {
      guard
        let bestRow = (pivot..<count).max(by: {
          abs(augmented[$0][pivot]) < abs(augmented[$1][pivot])
        }), abs(augmented[bestRow][pivot]) > 1e-10
      else {
        return nil
      }

      if bestRow != pivot {
        augmented.swapAt(bestRow, pivot)
      }

      let divisor = augmented[pivot][pivot]
      for column in pivot...count {
        augmented[pivot][column] /= divisor
      }

      for row in 0..<count where row != pivot {
        let factor = augmented[row][pivot]
        guard factor != 0 else { continue }
        for column in pivot...count {
          augmented[row][column] -= factor * augmented[pivot][column]
        }
      }
    }

    return augmented.map { $0[count] }
  }

  private func dot(_ lhs: [Double], _ rhs: [Double]) -> Double {
    zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
  }
}

extension Double {
  fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
