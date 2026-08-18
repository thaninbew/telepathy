import CoreGraphics

enum CalibrationTargetPlanner {
  static func points(in frame: CGRect) -> [CGPoint] {
    let horizontalInset = max(64, min(frame.width * 0.14, 160))
    let verticalInset = max(64, min(frame.height * 0.14, 120))

    return [
      CGPoint(x: frame.midX, y: frame.midY),
      CGPoint(x: frame.minX + horizontalInset, y: frame.maxY - verticalInset),
      CGPoint(x: frame.maxX - horizontalInset, y: frame.maxY - verticalInset),
      CGPoint(x: frame.maxX - horizontalInset, y: frame.minY + verticalInset),
      CGPoint(x: frame.minX + horizontalInset, y: frame.minY + verticalInset),
    ]
  }
}
