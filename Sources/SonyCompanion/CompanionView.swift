import SwiftUI
import SonyProtocol

struct CompanionView: View {
    @ObservedObject var controller: HeadphoneController
    @State private var showEQ = false
    private let accent = Color(red: 0.61, green: 0.83, blue: 0.55)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let notice = controller.notice {
                Label(notice, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if controller.state.ready {
                sourceControls
                Divider()
                noiseControls
                Divider()
                soundControls
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "headphones").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(accent)
                    Text("Your quiet, one click away.").font(.headline)
                    Text("Turn on your WH-1000XM5s and connect them in macOS Bluetooth settings. Allow Bluetooth access when prompted.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Open Bluetooth settings") { openSettings("com.apple.Bluetooth") }
                    Button("Bluetooth permissions") { openSettings("com.apple.preference.security?Privacy_Bluetooth") }
                        .buttonStyle(.link).font(.caption)
                }.frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            Divider()
            footer
        }
        .padding(20).frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .tint(accent)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "headphones").font(.system(size: 27)).foregroundStyle(accent)
                .frame(width: 48, height: 48).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text("Sony Companion").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(controller.state.ready ? accent : .orange).frame(width: 5, height: 5)
                    Text(controller.demo ? controller.status : controller.state.ready ? controller.deviceName : controller.status)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let battery = controller.state.battery {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(battery)%").font(.system(.title3, design: .rounded, weight: .semibold))
                    Text(controller.state.charging ? "Charging" : controller.state.codec ?? "Battery")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("AUDIO SOURCE")
                Spacer()
                Button { controller.refreshSources() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Refresh connected devices")
                    .disabled(controller.playbackDevices == nil || controller.demo || controller.switchingTo != nil)
            }
            if let devices = controller.playbackDevices, !devices.isEmpty {
                HStack(spacing: 8) {
                    Picker("Play from", selection: Binding(
                        get: { devices.first(where: \.playing)?.id ?? "" },
                        set: { id in
                            if let device = devices.first(where: { $0.id == id }) { controller.playFrom(device) }
                        }
                    )) {
                        if !devices.contains(where: \.playing) { Text("Choose device").tag("") }
                        ForEach(devices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .disabled(devices.count < 2 || controller.switchingTo != nil)
                    if controller.switchingTo != nil { ProgressView().controlSize(.small) }
                }
            }
            Text(controller.sourceStatus).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var noiseControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("YOUR SPACE")
            HStack(spacing: 6) {
                ForEach(NoiseMode.allCases, id: \.self) { mode in
                    Button { controller.setNoise(mode: mode) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: mode.symbol).font(.system(size: 20))
                            Text(mode == .cancelling ? "Quiet" : mode == .ambient ? "Ambient" : "Off").font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .foregroundStyle(controller.state.noise?.mode == mode ? Color.black : Color.primary)
                        .background(controller.state.noise?.mode == mode ? accent : Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(controller.state.noise == nil)
                }
            }
            if let noise = controller.state.noise, noise.mode == .ambient {
                HStack {
                    Text("Ambient level").font(.callout)
                    Spacer()
                    Text("\(noise.level) / 20").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                ConfirmedSlider(value: Double(noise.level), range: 1...20) { controller.setNoise(level: Int($0)) }
                Toggle("Focus on voice", isOn: Binding(get: { noise.focus }, set: { controller.setNoise(focus: $0) }))
                    .font(.callout).toggleStyle(.switch).controlSize(.small)
            }
        }
    }

    private var soundControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("YOUR SOUND")
            Picker("Equalizer", selection: Binding(get: { controller.state.preset ?? 0 }, set: {
                if let preset = EQPreset(rawValue: $0) { controller.setPreset(preset) }
            })) {
                ForEach(EQPreset.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                if let raw = controller.state.preset, EQPreset(rawValue: raw) == nil { Text("Unknown preset").tag(raw) }
            }.disabled(controller.state.preset == nil)
            DisclosureGroup("Adjust equalizer", isExpanded: $showEQ) {
                if let values = controller.state.eqValues {
                    VStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { index in
                            HStack {
                                Text(["Bass", "400", "1k", "2.5k", "6.3k", "16k"][index]).font(.caption).frame(width: 36, alignment: .leading)
                                ConfirmedSlider(value: Double(values[index]), range: -10...10) { controller.setEQ(index: index, value: Int($0)) }
                                Text(String(format: "%+d", values[index])).font(.caption.monospacedDigit()).frame(width: 28)
                            }
                        }
                    }.padding(.top, 8)
                } else { Text("Waiting for equalizer settings…").font(.caption) }
            }.font(.callout)
            Toggle("DSEE Extreme", isOn: Binding(get: { controller.state.dsee ?? false }, set: controller.setDSEE))
                .disabled(controller.state.dsee == nil)
            Toggle("Speak-to-Chat", isOn: Binding(get: { controller.state.speakToChat ?? false }, set: controller.setChat))
                .disabled(controller.state.speakToChat == nil)
        }.toggleStyle(.switch).controlSize(.small)
    }

    private var footer: some View {
        HStack {
            Button { controller.retry() } label: { Image(systemName: "arrow.clockwise") }
                .help("Reconnect to headphones").disabled(controller.demo)
            Button { openSettings("com.apple.Bluetooth") } label: { Image(systemName: "gearshape") }
                .help("Bluetooth settings")
            Spacer()
            if controller.demo { Text("DEMO").font(.caption2).foregroundStyle(.orange) }
            Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }.buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.8).foregroundStyle(.secondary)
    }
    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
    }
}

/// Keep a local drag value and send on release, then display headset confirmation.
private struct ConfirmedSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let commit: (Double) -> Void
    @State private var draft: Double = 0
    @State private var editing = false
    var body: some View {
        Slider(value: Binding(get: { editing ? draft : value }, set: { draft = $0 }), in: range, step: 1) { active in
            if active { draft = value; editing = true }
            else { editing = false; commit(draft) }
        }
        .accessibilityValue("\(Int(editing ? draft : value))")
    }
}
