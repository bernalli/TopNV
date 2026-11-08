import SwiftUI

struct SettingsView: View {
  @ObservedObject var settings: AppSettings
  @ObservedObject var loginItem: LoginItem
  @AppStorage(AppSettings.showMenuBarIconKey) private var showMenuBarIcon = true

  var body: some View {
    Form {
      Section("Display") {
        Toggle("Hide Notch", isOn: $settings.hideNotch)
        Toggle("Round Corners", isOn: $settings.roundCorners)
        VStack(alignment: .leading) {
          HStack {
            Text("Corner Radius")
            Spacer()
            Text("\(Int(settings.cornerRadius.rounded())) pt")
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
          Slider(value: $settings.cornerRadius, in: AppSettings.radiusRange, step: 1) {
            Text("Corner Radius")
          }
          .labelsHidden()
        }
        .disabled(!settings.roundCorners)
        Toggle("Corners on All Displays", isOn: $settings.cornersOnAllDisplays)
          .disabled(!settings.roundCorners)
      }

      Section("General") {
        Toggle(
          "Launch at Login",
          isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
        if let message = loginItem.errorMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        } else if loginItem.needsApproval {
          Text("Allow topNV in System Settings > General > Login Items.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Toggle("Show in Menu Bar", isOn: $showMenuBarIcon)
        Text("Open topNV again to bring the icon back.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .toggleStyle(.switch)
    .frame(width: 440)
    .fixedSize(horizontal: false, vertical: true)
    // Defer publishing until SwiftUI has finished laying out the Settings pane.
    .onAppear { Task { @MainActor in loginItem.refresh() } }
  }
}
