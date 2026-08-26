import Testing

@testable import Telepathy

struct CameraFrameRatePolicyTests {
  @Test func detailSelectsExpectedEnergyBudget() {
    #expect(CameraFrameRatePolicy.targetFramesPerSecond(for: .headOnly) == 15)
    #expect(CameraFrameRatePolicy.targetFramesPerSecond(for: .detailed) == 20)
  }

  @Test func supportedTargetIsPreferredOverRangeBoundary() {
    let ranges = [CameraFrameRateRange(minimum: 1, maximum: 30)]

    #expect(
      CameraFrameRatePolicy.supportedFramesPerSecond(for: .headOnly, ranges: ranges) == 15
    )
    #expect(
      CameraFrameRatePolicy.supportedFramesPerSecond(for: .detailed, ranges: ranges) == 20
    )
  }

  @Test func nearestSupportedBoundaryIsUsedWhenTargetIsUnavailable() {
    let ranges = [
      CameraFrameRateRange(minimum: 24, maximum: 30),
      CameraFrameRateRange(minimum: 60, maximum: 60),
    ]

    #expect(
      CameraFrameRatePolicy.supportedFramesPerSecond(for: .headOnly, ranges: ranges) == 24
    )
    #expect(
      CameraFrameRatePolicy.supportedFramesPerSecond(for: .detailed, ranges: ranges) == 24
    )
  }

  @Test func equallyCloseRatesPreferTheLowerEnergyOption() {
    let ranges = [
      CameraFrameRateRange(minimum: 10, maximum: 10),
      CameraFrameRateRange(minimum: 20, maximum: 20),
    ]

    #expect(
      CameraFrameRatePolicy.supportedFramesPerSecond(for: .headOnly, ranges: ranges) == 10
    )
  }

  @Test func invalidRangesDoNotProduceAnUnsafeDuration() {
    let ranges = [
      CameraFrameRateRange(minimum: 0, maximum: 30),
      CameraFrameRateRange(minimum: 30, maximum: 15),
      CameraFrameRateRange(minimum: .nan, maximum: 30),
    ]

    #expect(
      CameraFrameRatePolicy.supportedFramesPerSecond(for: .headOnly, ranges: ranges) == nil
    )
  }

  @Test func cadenceUsesTargetTimelineInsteadOfInputFrameSpacing() {
    var cadence = CameraFrameCadence()
    let timestamps = stride(from: 0.0, through: 0.2, by: 1.0 / 30.0)
    let accepted = timestamps.filter { cadence.shouldProcess(at: $0, detail: .detailed) }

    #expect(accepted.count == 5)
    #expect(accepted[0] == 0)
    #expect(accepted[1] > 0.03 && accepted[1] < 0.07)
  }

  @Test func cadenceResetMakesTheNextFrameImmediatelyEligible() {
    var cadence = CameraFrameCadence()
    let firstFrameAccepted = cadence.shouldProcess(at: 10, detail: .headOnly)
    let earlyFrameAccepted = cadence.shouldProcess(at: 10.01, detail: .headOnly)
    #expect(firstFrameAccepted)
    #expect(!earlyFrameAccepted)

    cadence.reset()

    let frameAfterResetAccepted = cadence.shouldProcess(at: 10.01, detail: .detailed)
    #expect(frameAfterResetAccepted)
  }

  @Test func laterStartInvalidatesAQueuedStop() {
    var intent = CameraLifecycleIntent()
    let stop = intent.requestStop()
    let start = intent.requestStart()

    #expect(!intent.permitsStop(stop))
    #expect(intent.permitsStart(start))
  }

  @Test func stopInvalidatesAPendingPermissionStart() {
    var intent = CameraLifecycleIntent()
    let start = intent.requestStart()
    let stop = intent.requestStop()

    #expect(!intent.permitsStart(start))
    #expect(intent.permitsStop(stop))
  }
}
