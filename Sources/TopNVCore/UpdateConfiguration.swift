import Foundation
import CoreFoundation

public struct UpdateConfiguration {
  public let isValid: Bool
  public init(infoDictionary: [String: Any]?) {
    guard let info = infoDictionary,
          let feed = info["SUFeedURL"] as? String,
          !feed.contains(where: { $0.isWhitespace }),
          let url = URLComponents(string: feed), url.scheme == "https",
          let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
          let encoded = info["SUPublicEDKey"] as? String,
          let key = Data(base64Encoded: encoded), key.count == 32 else {
      isValid = false; return
    }
    isValid = Self.boolean(info["SUEnableAutomaticChecks"], equals: false)
      && Self.boolean(info["SUAllowsAutomaticUpdates"], equals: false)
      && Self.boolean(info["SUVerifyUpdateBeforeExtraction"], equals: true)
  }
  private static func boolean(_ value: Any?, equals expected: Bool) -> Bool {
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
    return number.boolValue == expected
  }
}
