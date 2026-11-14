public struct MenuStatus {
  public let title: String
  public let symbol: String

  public init(hideNotch: Bool, roundCorners: Bool, localizer: Localizer = .main) {
    switch (hideNotch, roundCorners) {
    case (true, true):
      title = localizer(.notchHiddenCornersRounded)
      symbol = "display"
    case (true, false):
      title = localizer(.notchHidden)
      symbol = "menubar.rectangle"
    case (false, true):
      title = localizer(.cornersRounded)
      symbol = "rectangle"
    case (false, false):
      title = localizer(.inactive)
      symbol = "power"
    }
  }
}
