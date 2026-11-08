import AppKit
import TopNVCore

@MainActor
enum AboutPanel {
  static func show() {
    let credits = NSMutableAttributedString(
      string: "topNV hides the MacBook notch and rounds the screen corners.\n\n"
        + "Requires macOS 14 or later. Needs no Screen Recording or Accessibility permission.\n\n",
      attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
    if let url = AppLink.source.url {
      credits.append(NSAttributedString(
        string: url.absoluteString,
        attributes: [
          .link: url,
          .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ]))
    }

    NSApp.activate()
    // The standard panel reads the icon, name, version, build and copyright from the bundle.
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
  }
}
