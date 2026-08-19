import CoreGraphics

enum CalibrationTargetPurpose: Equatable {
  case posture
  case coverage
  case validation
}

struct PlannedCalibrationTarget: Equatable {
  let point: CGPoint
  let purpose: CalibrationTargetPurpose
}

enum CalibrationTargetPlanner {
  static func points(in frame: CGRect) -> [CGPoint] {
    let anchors = anchors(in: frame)

    return [
      CGPoint(x: frame.midX, y: frame.midY),
      anchors.upperLeft,
      anchors.upperRight,
      anchors.lowerRight,
      anchors.lowerLeft,
    ]
  }

  static func fullTrainingTargets(in frame: CGRect) -> [PlannedCalibrationTarget] {
    let anchors = anchors(in: frame)
    return [
      PlannedCalibrationTarget(
        point: CGPoint(x: frame.midX, y: frame.midY),
        purpose: .posture
      ),
      PlannedCalibrationTarget(point: anchors.leftMiddle, purpose: .coverage),
      PlannedCalibrationTarget(point: anchors.upperLeft, purpose: .coverage),
      PlannedCalibrationTarget(point: anchors.upperMiddle, purpose: .coverage),
      PlannedCalibrationTarget(point: anchors.upperRight, purpose: .coverage),
      PlannedCalibrationTarget(point: anchors.rightMiddle, purpose: .coverage),
      PlannedCalibrationTarget(point: anchors.lowerRight, purpose: .coverage),
      PlannedCalibrationTarget(point: anchors.lowerMiddle, purpose: .coverage),
      PlannedCalibrationTarget(point: anchors.lowerLeft, purpose: .coverage),
    ]
  }

  static func validationTargets(in frame: CGRect) -> [PlannedCalibrationTarget] {
    [
      PlannedCalibrationTarget(
        point: CGPoint(
          x: frame.minX + frame.width * 0.34,
          y: frame.minY + frame.height * 0.66
        ),
        purpose: .validation
      ),
      PlannedCalibrationTarget(
        point: CGPoint(
          x: frame.minX + frame.width * 0.68,
          y: frame.minY + frame.height * 0.36
        ),
        purpose: .validation
      ),
    ]
  }

  private struct Anchors {
    let leftMiddle: CGPoint
    let upperLeft: CGPoint
    let upperMiddle: CGPoint
    let upperRight: CGPoint
    let rightMiddle: CGPoint
    let lowerRight: CGPoint
    let lowerMiddle: CGPoint
    let lowerLeft: CGPoint
  }

  private static func anchors(in frame: CGRect) -> Anchors {
    let horizontalInset = max(64, min(frame.width * 0.14, 160))
    let verticalInset = max(64, min(frame.height * 0.14, 120))
    let left = frame.minX + horizontalInset
    let right = frame.maxX - horizontalInset
    let upper = frame.maxY - verticalInset
    let lower = frame.minY + verticalInset

    return Anchors(
      leftMiddle: CGPoint(x: left, y: frame.midY),
      upperLeft: CGPoint(x: left, y: upper),
      upperMiddle: CGPoint(x: frame.midX, y: upper),
      upperRight: CGPoint(x: right, y: upper),
      rightMiddle: CGPoint(x: right, y: frame.midY),
      lowerRight: CGPoint(x: right, y: lower),
      lowerMiddle: CGPoint(x: frame.midX, y: lower),
      lowerLeft: CGPoint(x: left, y: lower)
    )
  }
}
