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
      Text(information.version.title)
        .font(.system(size: NSFont.smallSystemFontSize))
        .foregroundStyle(.secondary)
      if let url = AppLink.source.url {
        Link("View Source on GitHub", destination: url)
          .font(.system(size: NSFont.smallSystemFontSize))
          .focusEffectDisabled()
      }
      if let copyright = information.copyright {
        Text(copyright)
          .font(.system(size: NSFont.smallSystemFontSize))
          .foregroundStyle(.secondary)
      }
      Button {
        guard let url = AppLink.sponsor.url else { return }
        NSWorkspace.shared.open(url)
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
