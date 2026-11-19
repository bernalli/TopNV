/// Test copies only: candidates for the normal luminance key, chosen by eye on the real menu bar.
/// Screenshots do not contain the keyed layer, so the key cannot be measured from them. The
/// production bundle identifier never gets a calibration, and the choice is never saved.
public struct KeyCalibration: Equatable, Sendable {
  public let gain: Float
  public let cutoff: Float
  public let curve: KeyCurve?
  public let title: String
  public let command: MenuCommand

  public static let productionBundleIdentifier = "io.github.bernalli.topnv"

  /// The first candidate is the production normal key: a test copy starts with it. The others
  /// add the curve, then raise the black point to 0.47, 0.56 and 0.65.
  public static let options: [KeyCalibration] = [
    KeyCalibration(
      gain: 3, cutoff: 0.21, curve: nil, title: "3 / 0.21 (1.2.5)", command: .keyCalibration1),
    KeyCalibration(
      gain: 3, cutoff: 0.21, curve: .soft, title: "3 / 0.21 + soft curve", command: .keyCalibration2),
    KeyCalibration(
      gain: 3, cutoff: 0.21, curve: .strong, title: "3 / 0.21 + strong curve", command: .keyCalibration3),
    KeyCalibration(
      gain: 2.3, cutoff: 0.255, curve: .soft, title: "2.3 / 0.255 + soft curve", command: .keyCalibration4),
    KeyCalibration(
      gain: 1.9, cutoff: 0.3, curve: .soft, title: "1.9 / 0.3 + soft curve", command: .keyCalibration5),
    KeyCalibration(
      gain: 1.65, cutoff: 0.345, curve: .soft, title: "1.65 / 0.345 + soft curve", command: .keyCalibration6)
  ]

  private init(gain: Float, cutoff: Float, curve: KeyCurve?, title: String, command: MenuCommand) {
    self.gain = gain
    self.cutoff = cutoff
    self.curve = curve
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
        && $0.curve == LuminanceKey.normal.curve
    }
  }

  public static func option(for command: MenuCommand) -> KeyCalibration? {
    options.first { $0.command == command }
  }

  /// The matrix of the normal key: the chosen candidate, without a calibration the production
  /// key. The revealed key is never calibrated.
  public static func normalMatrix(_ calibration: KeyCalibration?) -> [Float] {
    guard let calibration else { return LuminanceKey.normal.matrix }
    return LuminanceKey.matrix(gain: calibration.gain, cutoff: calibration.cutoff)
  }

  /// The curve of the normal key: the chosen candidate's, without a calibration the production one.
  public static func normalCurve(_ calibration: KeyCalibration?) -> KeyCurve? {
    guard let calibration else { return LuminanceKey.normal.curve }
    return calibration.curve
  }
}
