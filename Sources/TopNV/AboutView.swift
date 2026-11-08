import AppKit
import SwiftUI
import TopNVCore

struct AboutView: View {
  let information: AboutInformation

  var body: some View {
    VStack(spacing: 8) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .scaledToFit()
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
        .padding(.bottom, 4)
      Text(information.name)
        .font(.system(size: 16, weight: .bold))
      HStack(spacing: 6) {
        Text(information.version.title)
          .font(.system(size: NSFont.smallSystemFontSize))
          .foregroundStyle(.secondary)
        Button {
          open(.source)
        } label: {
          GitHubMark()
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help("View Source on GitHub")
        .accessibilityLabel("View Source on GitHub")
      }
      if let copyright = information.copyright {
        Text(copyright)
          .font(.system(size: NSFont.smallSystemFontSize))
          .foregroundStyle(.secondary)
      }
      Button {
        open(.sponsor)
      } label: {
        Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
      }
      .buttonStyle(CoffeeButtonStyle())
      .focusEffectDisabled()
      .padding(.top, 8)
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .padding(20)
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

private struct CoffeeButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: NSFont.smallSystemFontSize))
      .foregroundStyle(.primary)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      // Native bordered buttons ignore capsule border shapes on macOS 14.
      .background(.primary.opacity(configuration.isPressed ? 0.12 : 0.04), in: Capsule())
      .overlay {
        Capsule().strokeBorder(.primary.opacity(0.2), lineWidth: 1)
      }
  }
}
