public struct MenuStatus {
  public let title: String
  public let symbol: String

  public init(hideNotch: Bool, roundCorners: Bool) {
    switch (hideNotch, roundCorners) {
    case (true, true):
      title = "Notch Hidden, Corners Rounded"
      symbol = "display"
    case (true, false):
      title = "Notch Hidden"
      symbol = "menubar.rectangle"
    case (false, true):
      title = "Corners Rounded"
      symbol = "rectangle"
    case (false, false):
      title = "Inactive"
      symbol = "power"
    }
  }
}
