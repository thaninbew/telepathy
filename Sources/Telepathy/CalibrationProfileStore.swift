import Foundation

final class CalibrationProfileStore {
  private struct Profiles: Codable {
    var samplesByLayout: [String: [CalibrationSample]]
  }

  private let defaults: UserDefaults
  private let profilesKey: String
  private let legacySamplesKey: String

  init(
    defaults: UserDefaults = .standard,
    profilesKey: String = "telepathy.calibrationProfiles.v1",
    legacySamplesKey: String = "telepathy.calibrationSamples.v1"
  ) {
    self.defaults = defaults
    self.profilesKey = profilesKey
    self.legacySamplesKey = legacySamplesKey
  }

  func load(layout: String) -> [CalibrationSample]? {
    if let samples = loadProfiles().samplesByLayout[layout] {
      return samples
    }

    guard let data = defaults.data(forKey: legacySamplesKey),
      let samples = try? JSONDecoder().decode([CalibrationSample].self, from: data)
    else {
      return nil
    }

    save(samples: samples, layout: layout)
    defaults.removeObject(forKey: legacySamplesKey)
    return samples
  }

  func save(samples: [CalibrationSample], layout: String) {
    var profiles = loadProfiles()
    profiles.samplesByLayout[layout] = samples
    guard let data = try? JSONEncoder().encode(profiles) else { return }
    defaults.set(data, forKey: profilesKey)
  }

  func remove(layout: String) {
    var profiles = loadProfiles()
    profiles.samplesByLayout.removeValue(forKey: layout)
    guard let data = try? JSONEncoder().encode(profiles) else { return }
    defaults.set(data, forKey: profilesKey)
  }

  private func loadProfiles() -> Profiles {
    guard let data = defaults.data(forKey: profilesKey),
      let profiles = try? JSONDecoder().decode(Profiles.self, from: data)
    else {
      return Profiles(samplesByLayout: [:])
    }
    return profiles
  }
}
