import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: DockController
    @ObservedObject var updateController: UpdateController

    var body: some View {
        Form {
            Section("Position & Edge Hover") {
                Picker("Screen position", selection: $controller.screenAlignment) {
                    ForEach(DockScreenAlignment.allCases) { alignment in
                        Label(alignment.title, systemImage: alignment.symbolName)
                            .tag(alignment)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Spacer(minLength: 0)
                    DockPositionPreview(
                        alignment: $controller.screenAlignment,
                        revealZoneWidth: controller.revealZoneWidth,
                        edgeHoverEnabled: controller.edgeHoverEnabled
                    )
                    Spacer(minLength: 0)
                }

                Text(positionHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Reveal from screen edge", isOn: $controller.edgeHoverEnabled)
                    .tint(.blue)

                LabeledContent("Hover-zone width") {
                    HStack(spacing: 10) {
                        Slider(value: $controller.revealZoneWidth, in: 80...600, step: 20)
                            .frame(width: 190)
                        Text("\(Int(controller.revealZoneWidth)) px")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 54, alignment: .trailing)
                    }
                }
                .disabled(!controller.edgeHoverEnabled)

                Text("The highlighted strip in the preview is the active hover zone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Open Folder Dock") {
                LabeledContent {
                    Button("Show Now") {
                        controller.toggleFromMenuBar()
                    }
                } label: {
                    Label("Menu-bar button", systemImage: "menubar.rectangle")
                }

                Text("Click the Folder Dock menu-bar icon to show or hide the panel. Right-click it for more options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                LabeledContent {
                    Text("⌥E")
                        .monospaced()
                } label: {
                    Label("Show / hide shortcut", systemImage: "keyboard")
                }

                Text("Press Option-E anywhere to toggle Folder Dock. Set-switch shortcuts are disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Auto-Close Behavior") {
                Text(howItWorksText)
                    .font(.callout)

                VStack(alignment: .leading, spacing: 6) {
                    Label("Edge hover: hides shortly after the pointer leaves.", systemImage: "cursorarrow.motionlines")
                    Label("After interacting: closes after the pointer remains outside for 3 seconds.", systemImage: "hand.tap")
                    Label("Menu bar or ⌥E: closes on another-app click or after 5 seconds without interaction.", systemImage: "timer")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Updates") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Folder Dock \(versionText)")
                            Text(updateStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(updateController.isUpdateAvailable ? "Update" : "Check Now") {
                            if updateController.isUpdateAvailable {
                                updateController.checkForUpdates()
                            } else {
                                updateController.probeForUpdate()
                            }
                        }
                        .disabled(updateController.isChecking)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.secondary)
                        Text("Automatic installation requires App Management permission.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open App Management") {
                            updateController.openAppManagementSettings()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 650)
        .padding()
        .onAppear {
            DispatchQueue.main.async {
                NSApp.activate()
                NSApp.windows.first(where: { $0.title == "Folder Dock Settings" })?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        return "\(version) (B\(build))"
    }

    private var positionHelpText: String {
        switch controller.screenAlignment {
        case .left:
            "The dock is anchored to the top-left and grows toward the right when resized."
        case .center:
            "The dock stays centered and grows equally in both directions when resized."
        case .right:
            "The dock is anchored to the top-right and grows toward the left when resized."
        }
    }

    private var howItWorksText: String {
        if controller.edgeHoverEnabled {
            return "Use ⌥E, click the menu-bar icon, or move the pointer to the selected top edge of any display."
        }
        return "Use ⌥E or click the Folder Dock menu-bar icon to show or hide the panel."
    }

    private var updateStatusText: String {
        if updateController.isChecking { return "Checking for updates…" }
        if let availableVersion = updateController.availableVersion {
            return "Version \(availableVersion) is available."
        }
        return "Updates are checked securely from GitHub Releases."
    }
}

private struct DockPositionPreview: View {
    @Binding var alignment: DockScreenAlignment
    let revealZoneWidth: Double
    let edgeHoverEnabled: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let margin: CGFloat = 10
            let shelfWidth = min(150, size.width * 0.43)
            let browserWidth = min(178, size.width * 0.52)
            let shelfHeight = max(24, size.height * 0.13)
            let shelfY = max(18, size.height * 0.09)
            let browserY = shelfY + shelfHeight + 7
            let browserHeight = max(76, size.height - browserY - 12)
            let shelfX = originX(width: shelfWidth, availableWidth: size.width, margin: margin)
            let browserX = originX(width: browserWidth, availableWidth: size.width, margin: margin)
            let revealWidth = previewRevealWidth(for: size.width)
            let revealX = originX(width: revealWidth, availableWidth: size.width, margin: 1)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                    }

                Rectangle()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: 12)
                    .clipShape(.rect(topLeadingRadius: 12, topTrailingRadius: 12))

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: revealWidth, height: 3)
                    .offset(x: revealX, y: 1)
                    .opacity(edgeHoverEnabled ? 1 : 0)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.78))
                    .frame(width: shelfWidth, height: shelfHeight)
                    .overlay {
                        HStack(spacing: 4) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.72))
                                    .frame(width: 16, height: 12)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 7)
                    }
                    .offset(x: shelfX, y: shelfY)
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 2)

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.secondary.opacity(0.23))
                    .overlay {
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.35))
                                .frame(height: 8)
                            HStack(spacing: 5) {
                                ForEach(0..<3, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.secondary.opacity(0.28))
                                }
                            }
                        }
                        .padding(7)
                    }
                    .frame(width: browserWidth, height: browserHeight)
                    .offset(x: browserX, y: browserY)

                HStack(spacing: 0) {
                    ForEach(DockScreenAlignment.allCases) { option in
                        Button {
                            alignment = option
                        } label: {
                            Color.clear
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Use \(option.title)")
                    }
                }
            }
            .animation(.snappy(duration: 0.22), value: alignment)
            .animation(.snappy(duration: 0.18), value: revealZoneWidth)
            .animation(.snappy(duration: 0.18), value: edgeHoverEnabled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dock position preview")
            .accessibilityValue(alignment.title)
        }
        .frame(width: previewWidth, height: previewHeight)
    }

    private func originX(width: CGFloat, availableWidth: CGFloat, margin: CGFloat) -> CGFloat {
        switch alignment {
        case .left:
            margin
        case .center:
            (availableWidth - width) / 2
        case .right:
            availableWidth - width - margin
        }
    }

    private var previewWidth: CGFloat { 340 }

    private var previewHeight: CGFloat {
        previewWidth / activeDisplayAspectRatio
    }

    private var activeDisplayAspectRatio: CGFloat {
        let size = activeDisplaySize
        guard size.height > 0 else { return 16.0 / 10.0 }
        return size.width / size.height
    }

    private var activeDisplaySize: CGSize {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        return screen?.frame.size ?? CGSize(width: 1_600, height: 1_000)
    }

    private func previewRevealWidth(for availableWidth: CGFloat) -> CGFloat {
        let screenWidth = max(activeDisplaySize.width, 1)
        return min(availableWidth - 2, max(10, availableWidth * CGFloat(revealZoneWidth) / screenWidth))
    }
}
