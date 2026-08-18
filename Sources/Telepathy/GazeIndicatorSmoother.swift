import CoreGraphics

struct GazeIndicatorSmoother {
  private(set) var point: CGPoint?
  let newSampleWeight: CGFloat

  init(newSampleWeight: CGFloat = 0.22) {
    self.newSampleWeight = newSampleWeight
  }

  mutating func update(with sample: CGPoint) -> CGPoint {
    guard let point else {
      self.point = sample
      return sample
    }

    let filtered = CGPoint(
      x: sample.x * newSampleWeight + point.x * (1 - newSampleWeight),
      y: sample.y * newSampleWeight + point.y * (1 - newSampleWeight)
    )
    self.point = filtered
    return filtered
  }

  mutating func reset() {
    point = nil
  }
}
