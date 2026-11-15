import AppKit
import SwiftUI
import TopNVCore

enum AboutArtwork {
  /// Loads a vector mark as a template image, so it is drawn in the text colour: black in light
  /// mode and white in dark mode, with its own proportions.
  static func templateImage(contentsOf url: URL?) -> NSImage? {
    guard let url, let image = NSImage(contentsOf: url) else { return nil }
    image.isTemplate = true
    return image
  }
}

/// The content of the standard About panel (icon, name, version, copyright) plus a GitHub link
/// beside the version and a sponsor button, as in MonoPods. Its texts are always English (D-35).
struct AboutView: View {
  let information: AboutInformation
  let icon: NSImage?
  let gitHubMark: NSImage?
  let titleFont: NSFont
  let openRepository: @MainActor () -> Void
  let openSponsors: @MainActor () -> Void

  private static let iconSide: CGFloat = 64
  private static let detailSize = NSFont.smallSystemFontSize
  private static let markSide: CGFloat = 12
  private static let width: CGFloat = 280

  var body: some View {
    VStack(spacing: 0) {
      if let icon {
        Image(nsImage: icon)
          .resizable()
          .interpolation(.high)
          .frame(width: Self.iconSide, height: Self.iconSide)
          .accessibilityHidden(true)
      }
      Text(verbatim: information.name)
        .font(Font(titleFont))
        .padding(.top, 10)
      HStack(spacing: 5) {
        Text(verbatim: information.version.title)
        if let gitHubMark {
          Button(action: openRepository) {
            Image(nsImage: gitHubMark)
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: Self.markSide, height: Self.markSide)
          }
          .buttonStyle(.plain)
          .foregroundStyle(.primary)
          .help(AboutText.gitHubHelp)
          .accessibilityLabel(AboutText.gitHubHelp)
        }
      }
      .font(.system(size: Self.detailSize))
      .foregroundStyle(.secondary)
      .padding(.top, 4)
      if let copyright = information.copyright {
        Text(verbatim: copyright)
          .font(.system(size: Self.detailSize))
          .foregroundStyle(.secondary)
          .padding(.top, 10)
      }
      Button(action: openSponsors) {
        Label(AboutText.sponsor, systemImage: "cup.and.saucer")
      }
      .controlSize(.small)
      .padding(.top, 14)
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 20)
    .padding(.top, 6)
    .padding(.bottom, 20)
    .frame(width: Self.width)
  }
}
