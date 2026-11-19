/// Test copies only: candidates for the normal luminance key, chosen by eye on the real menu bar.
/// Screenshots do not contain the keyed layer, so the key cannot be measured from them. The
/// production bundle identifier never gets a calibration, and the choice is never saved.
public struct KeyCalibration: Equatable, Sendable {
  public let gain: Float
  public let cutoff: Float
  public let title: String
  public let command: MenuCommand

  public static let productionBundleIdentifier = "io.github.bernalli.topnv"

  /// The fifth candidate is the production normal key: a test copy starts with it.
  public static let options: [KeyCalibration] = [
    KeyCalibration(gain: 12, cutoff: 0.228, title: "12 / 0.228 (1.2.4)", command: .keyCalibration1),
    KeyCalibration(gain: 6, cutoff: 0.2, title: "6 / 0.2", command: .keyCalibration2),
    KeyCalibration(gain: 4.5, cutoff: 0.2, title: "4.5 / 0.2", command: .keyCalibration3),
    KeyCalibration(gain: 3.6, cutoff: 0.19, title: "3.6 / 0.19", command: .keyCalibration4),
    KeyCalibration(gain: 3, cutoff: 0.21, title: "3 / 0.21", command: .keyCalibration5),
    KeyCalibration(gain: 2.4, cutoff: 0.25, title: "2.4 / 0.25", command: .keyCalibration6)
  ]

  private init(gain: Float, cutoff: Float, title: String, command: MenuCommand) {
    self.gain = gain
    self.cutoff = cutoff
    self.title = title
    self.command = command
  }

  /// The calibration a copy starts with. Nil for the production bundle identifier in any case,
  /// and also without an identifier: a copy that cannot be told apart behaves as production.
  public static func initial(bundleIdentifier: String?) -> KeyCalibration? {
    guard let bundleIdentifier, !bundleIdentifier.isEmpty,
          bundleIdentifier.lowercased() != productionBundleIdentifier else { return nil }
    return options.first {
      $0.gain == LuminanceKey.normal.gain && $0.cutoff == LuminanceKey.normal.cutoff
    }
  }

  public static func option(for command: MenuCommand) -> KeyCalibration? {
    options.first { $0.command == command }
  }

  /// The matrix of the normal key: the chosen candidate, without a calibration the production
  /// key.
  public static func normalMatrix(_ calibration: KeyCalibration?) -> [Float] {
    guard let calibration else { return LuminanceKey.normal.matrix }
    return LuminanceKey.matrix(gain: calibration.gain, cutoff: calibration.cutoff)
  }
}
