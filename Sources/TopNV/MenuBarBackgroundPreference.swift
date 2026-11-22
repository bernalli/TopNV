import Foundation

/// Reads just the system menu material preference, at most once a second on the existing sampler.
struct MenuBarBackgroundPreference {
  private var nextRead = -Double.infinity
  private var enabled = false

  mutating func value(at uptime: Double, read: () -> Bool = systemValue) -> Bool {
    if uptime >= nextRead {
      enabled = read()
      nextRead = uptime + 1
    }
    return enabled
  }

  private static func systemValue() -> Bool {
    let value = CFPreferencesCopyValue("SLSMenuBarUseBlurredAppearance" as CFString, kCFPreferencesAnyApplication,
                                       kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    return (value as? NSNumber)?.boolValue ?? false
  }
}
