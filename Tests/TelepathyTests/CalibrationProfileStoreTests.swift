import Foundation
import XCTest

@testable import Telepathy

final class CalibrationProfileStoreTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "CalibrationProfileStoreTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testSavesIndependentLayouts() {
    let store = CalibrationProfileStore(defaults: defaults)
    let first = [sample(x: 0.1, y: 0.2)]
    let second = [sample(x: 0.8, y: 0.7)]

    store.save(samples: first, layout: "desk")
    store.save(samples: second, layout: "travel")

    XCTAssertEqual(store.load(layout: "desk"), first)
    XCTAssertEqual(store.load(layout: "travel"), second)
  }

  func testMigratesLegacySamplesToCurrentLayout() throws {
    let legacyKey = "legacy"
    let profilesKey = "profiles"
    let samples = [sample(x: 0.4, y: 0.6)]
    defaults.set(try JSONEncoder().encode(samples), forKey: legacyKey)
    let store = CalibrationProfileStore(
      defaults: defaults,
      profilesKey: profilesKey,
      legacySamplesKey: legacyKey
    )

    XCTAssertEqual(store.load(layout: "current"), samples)
    XCTAssertNil(defaults.data(forKey: legacyKey))
    XCTAssertEqual(store.load(layout: "current"), samples)
  }

  func testRemoveOnlyClearsRequestedLayout() {
    let store = CalibrationProfileStore(defaults: defaults)
    let desk = [sample(x: 0.1, y: 0.2)]
    let travel = [sample(x: 0.8, y: 0.7)]
    store.save(samples: desk, layout: "desk")
    store.save(samples: travel, layout: "travel")

    store.remove(layout: "desk")

    XCTAssertNil(store.load(layout: "desk"))
    XCTAssertEqual(store.load(layout: "travel"), travel)
  }

  func testDecodesProfilesWithoutRemovedExpressionMetrics() throws {
    let json = """
      [{"features":{"timestamp":1,"faceX":0.5,"faceY":0.5,"yaw":0,"pitch":0,"pupilX":0.5,"pupilY":0.5,"confidence":1},"normalizedX":0.2,"normalizedY":0.3}]
      """
    let samples = try JSONDecoder().decode([CalibrationSample].self, from: Data(json.utf8))

    XCTAssertEqual(samples.count, 1)
    XCTAssertEqual(samples[0].features.vector, [1, 0.5, 0.5, 0, 0, 0.5, 0.5])
  }

  private func sample(x: Double, y: Double) -> CalibrationSample {
    CalibrationSample(
      features: GazeFeatures(
        timestamp: 1,
        faceX: 0.5,
        faceY: 0.5,
        yaw: 0,
        pitch: 0,
        pupilX: 0.5,
        pupilY: 0.5,
        confidence: 1
      ),
      normalizedX: x,
      normalizedY: y
    )
  }
}
