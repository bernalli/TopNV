import AppKit
import SwiftUI
import TopNVCore

struct AboutView: View {
  let information: AboutInformation
  private let localizer = Localizer.main

  var body: some View {
    VStack(spacing: 0) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .scaledToFit()
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
      Text(verbatim: information.name)
        .font(.system(size: 16, weight: .bold))
        .padding(.top, 10)
      HStack(spacing: 5) {
        Text(verbatim: information.version.title)
        Button {
          open(.source)
        } label: {
          GitHubMark()
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(localizer(.viewOnGitHub, information.name))
        .accessibilityLabel(localizer(.viewOnGitHub, information.name))
      }
      .font(.system(size: NSFont.smallSystemFontSize))
      .foregroundStyle(.secondary)
      .padding(.top, 4)
      if let copyright = information.copyright {
        Text(verbatim: copyright)
          .font(.system(size: NSFont.smallSystemFontSize))
          .foregroundStyle(.secondary)
          .padding(.top, 10)
      }
      Button {
        open(.sponsor)
      } label: {
        Label(localizer(.buyMeACoffee), systemImage: "cup.and.saucer")
      }
      .controlSize(.small)
      .padding(.top, 14)
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 20)
    .padding(.top, 6)
    .padding(.bottom, 20)
    .frame(width: 280)
  }

  private func open(_ link: AppLink) {
    guard let url = link.url else { return }
    NSWorkspace.shared.open(url)
  }
}

/// The GitHub mark from the app bundle, or an SF Symbol when run unbundled.
private struct GitHubMark: View {
  private static let image: NSImage? = {
    guard let image = Bundle.main.image(forResource: "GitHubMark") else { return nil }
    image.isTemplate = true
    image.size = NSSize(width: 12, height: 12)
    return image
  }()

  var body: some View {
    Group {
      if let image = Self.image {
        Image(nsImage: image)
      } else {
        Image(systemName: "link")
      }
    }
    .foregroundStyle(.secondary)
  }
}
