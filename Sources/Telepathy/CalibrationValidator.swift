import CoreGraphics
import Foundation

struct CalibrationValidationObservation: Equatable {
  let expectedDisplayID: CGDirectDisplayID
  let features: GazeFeatures
}

struct CalibrationValidationResult: Equatable {
  let passed: Bool
  let overallAccuracy: Double
  let accuracyByDisplay: [CGDirectDisplayID: Double]
}

enum CalibrationValidator {
  static let minimumOverallAccuracy = 0.7
  static let minimumPerDisplayAccuracy = 0.6

  static func evaluate(
    trainingSamples: [CalibrationSample],
    observations: [CalibrationValidationObservation],
    desktopBounds: CGRect,
    displays: [ActiveDisplay]
  ) -> CalibrationValidationResult {
    guard displays.count > 1 else {
      return CalibrationValidationResult(
        passed: true,
        overallAccuracy: 1,
        accuracyByDisplay: displays.reduce(into: [:]) { $0[$1.id] = 1 }
      )
    }

    let requiredDisplayIDs = Set(displays.map(\.id))
    let observedDisplayIDs = Set(observations.map(\.expectedDisplayID))
    guard observedDisplayIDs == requiredDisplayIDs, !observations.isEmpty else {
      return CalibrationValidationResult(
        passed: false,
        overallAccuracy: 0,
        accuracyByDisplay: [:]
      )
    }

    let classifier = HeadDisplayClassifier()
    classifier.fit(
      samples: trainingSamples,
      desktopBounds: desktopBounds,
      displays: displays
    )
    guard classifier.isReady else {
      return CalibrationValidationResult(
        passed: false,
        overallAccuracy: 0,
        accuracyByDisplay: [:]
      )
    }

    var totals: [CGDirectDisplayID: Int] = [:]
    var correct: [CGDirectDisplayID: Int] = [:]
    for observation in observations {
      totals[observation.expectedDisplayID, default: 0] += 1
      if classifier.predict(features: observation.features)?.displayID
        == observation.expectedDisplayID
      {
        correct[observation.expectedDisplayID, default: 0] += 1
      }
    }

    var keyedAccuracy: [CGDirectDisplayID: Double] = [:]
    for (displayID, total) in totals {
      keyedAccuracy[displayID] = Double(correct[displayID, default: 0]) / Double(total)
    }

    let totalCorrect = correct.values.reduce(0, +)
    let overallAccuracy = Double(totalCorrect) / Double(observations.count)
    let passed =
      overallAccuracy >= minimumOverallAccuracy
      && requiredDisplayIDs.allSatisfy {
        keyedAccuracy[$0, default: 0] >= minimumPerDisplayAccuracy
      }

    return CalibrationValidationResult(
      passed: passed,
      overallAccuracy: overallAccuracy,
      accuracyByDisplay: keyedAccuracy
    )
  }
}
