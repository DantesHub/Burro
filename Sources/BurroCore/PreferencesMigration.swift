// Preserve the original app's explicit preferences once, without copying unrelated system defaults.
import Foundation

public enum PreferencesMigration {
    public static let marker = "migratedGrovePreferences"
    public static let keys = ["repositories", "protectedPaths", "discover", "baseOverrides"]
    public static func migrate(into destination: UserDefaults, legacy: [String: Any]) {
        guard !destination.bool(forKey: marker) else { return }
        for key in keys where destination.object(forKey: key) == nil {
            if let value = legacy[key] { destination.set(value, forKey: key) }
        }
        destination.set(true, forKey: marker)
    }
}
