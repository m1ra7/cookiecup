import Foundation

/// Retains the same Codable payload and fallback key as the previous version.
/// Existing favorites, cart options and order history can be decoded unchanged.
@MainActor final class Persistence {
    private let fallbackKey = "cookiecup.snapshot.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> SavedState {
        guard let data = defaults.data(forKey: fallbackKey),
              let state = try? JSONDecoder().decode(SavedState.self, from: data)
        else { return SavedState() }
        return state
    }

    @discardableResult func save(_ state: SavedState) -> Bool {
        guard let data = try? JSONEncoder().encode(state) else { return false }
        defaults.set(data, forKey: fallbackKey)
        return true
    }
}
