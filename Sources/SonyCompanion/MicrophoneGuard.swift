import Foundation
import Combine
import CoreAudio

struct AudioInput: Equatable {
    var id: AudioDeviceID
    var name: String
    var builtIn: Bool
}

struct AudioRoute {
    var inputs: [AudioInput]
    var defaultInput: AudioDeviceID
    var sonyOutput: Bool
    var outputRate: Double?
    var outputChannels: Int
    var outputID: AudioDeviceID = 0
    var builtInOutputID: AudioDeviceID? = nil
}

protocol AudioRouting: AnyObject {
    func route() -> AudioRoute
    func setInput(_ id: AudioDeviceID) -> OSStatus
    func setOutput(_ id: AudioDeviceID) -> OSStatus
    func observe(_ changed: @escaping () -> Void)
    func stopObserving()
}

/// Keeps the default input on the Mac and offers an explicit output reset.
/// Never opens or records a microphone.
final class MicrophoneGuard: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var inputName = "Reading audio input…"
    @Published private(set) var outputDescription = ""
    @Published private(set) var message = ""
    @Published private(set) var canResetOutput = false
    @Published private(set) var resettingOutput = false
    private var pendingOutputRestore: (temporary: AudioDeviceID, headphones: AudioDeviceID)?
    private let routing: AudioRouting
    private let defaults: UserDefaults
    private let demo: Bool
    private var timer: Timer?
    private static let preference = "useMacMicrophone"

    init(routing: AudioRouting = CoreAudioRouting(), defaults: UserDefaults = .standard, demo: Bool = false) {
        self.routing = routing; self.defaults = defaults; self.demo = demo
        enabled = defaults.object(forKey: Self.preference) == nil || defaults.bool(forKey: Self.preference)
    }

    func start() {
        guard !demo else {
            inputName = "MacBook Microphone"; outputDescription = "48 kHz · Stereo"; message = "Demo · no audio settings changed."
            return
        }
        routing.observe { [weak self] in self?.refresh() }
        // Sample-rate changes can happen without changing the default device.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refresh()
    }

    func stop() {
        finishOutputReset()
        timer?.invalidate(); timer = nil; routing.stopObserving()
    }

    func resetOutput() {
        guard !demo, !resettingOutput else { return }
        let route = routing.route()
        guard route.sonyOutput, let speaker = route.builtInOutputID, route.outputID != 0 else { return }
        resettingOutput = true
        pendingOutputRestore = (speaker, route.outputID)
        let result = routing.setOutput(speaker)
        guard result == noErr else {
            pendingOutputRestore = nil; resettingOutput = false
            message = "Could not reselect audio output (\(result))."; return
        }
        message = "Re-selecting headphone output…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.finishOutputReset() }
    }

    private func finishOutputReset() {
        guard let restore = pendingOutputRestore else { return }
        pendingOutputRestore = nil
        // Respect an output the user selected while the reset was in progress.
        var result: OSStatus = noErr
        if routing.route().outputID == restore.temporary { result = routing.setOutput(restore.headphones) }
        resettingOutput = false
        refresh()
        if result != noErr { message = "Could not restore the headphones. Select them in Sound settings (\(result))." }
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        guard !demo else { return }
        defaults.set(on, forKey: Self.preference)
        refresh()
    }

    func refresh() {
        guard !demo else { return }
        var route = routing.route()
        canResetOutput = route.sonyOutput && route.builtInOutputID != nil
        message = resettingOutput ? "Re-selecting headphone output…" : ""
        if enabled, route.sonyOutput {
            if let builtIn = route.inputs.first(where: \.builtIn) {
                if route.defaultInput != builtIn.id {
                    let status = routing.setInput(builtIn.id)
                    if status == noErr {
                        route = routing.route() // Report what CoreAudio confirms.
                        if route.defaultInput != builtIn.id { message = "Waiting for macOS to select the Mac microphone." }
                    } else { message = "Could not select the Mac microphone (\(status))." }
                }
            } else { message = "No built-in microphone is available. Select a wired or USB mic in Sound settings." }
        }
        inputName = route.inputs.first(where: { $0.id == route.defaultInput })?.name ?? "No input selected"
        if route.sonyOutput, let rate = route.outputRate {
            let channels = route.outputChannels == 1 ? "Mono" : route.outputChannels == 2 ? "Stereo" : "\(route.outputChannels) channels"
            outputDescription = "\(String(format: "%g", rate / 1000)) kHz · \(channels)"
            if rate <= 24000, message.isEmpty {
                message = "Low-bandwidth output detected. Check the microphone selected inside your calling app and end any phone call."
            }
        } else { outputDescription = "" }
    }
}

final class CoreAudioRouting: AudioRouting {
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func route() -> AudioRoute {
        let devices = deviceIDs()
        let input: AudioDeviceID = scalar(system, kAudioHardwarePropertyDefaultInputDevice) ?? 0
        let output: AudioDeviceID = scalar(system, kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        let inputs = devices.compactMap { device -> AudioInput? in
            guard channels(device, scope: kAudioObjectPropertyScopeInput) > 0 else { return nil }
            let transport: UInt32? = scalar(device, kAudioDevicePropertyTransportType)
            return AudioInput(id: device, name: name(device), builtIn: transport == kAudioDeviceTransportTypeBuiltIn)
        }
        let outputName = name(output).uppercased()
        let transport: UInt32? = scalar(output, kAudioDevicePropertyTransportType)
        let sony = outputName.contains("WH-1000XM5") && [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE].contains(transport ?? 0)
        return AudioRoute(inputs: inputs, defaultInput: input, sonyOutput: sony,
                          outputRate: scalar(output, kAudioDevicePropertyNominalSampleRate),
                          outputChannels: channels(output, scope: kAudioObjectPropertyScopeOutput), outputID: output,
                          builtInOutputID: devices.first { device in
                              let transport: UInt32? = scalar(device, kAudioDevicePropertyTransportType)
                              return transport == kAudioDeviceTransportTypeBuiltIn && channels(device, scope: kAudioObjectPropertyScopeOutput) > 0
                          })
    }

    func setInput(_ id: AudioDeviceID) -> OSStatus {
        var address = property(kAudioHardwarePropertyDefaultInputDevice)
        var device = id
        return AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: device)), &device)
    }

    func setOutput(_ id: AudioDeviceID) -> OSStatus {
        var address = property(kAudioHardwarePropertyDefaultOutputDevice)
        var device = id
        return AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: device)), &device)
    }

    func observe(_ changed: @escaping () -> Void) {
        stopObserving()
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var address = property(selector)
            let listener: AudioObjectPropertyListenerBlock = { _, _ in changed() }
            if AudioObjectAddPropertyListenerBlock(system, &address, .main, listener) == noErr {
                listeners.append((address, listener))
            }
        }
    }

    func stopObserving() {
        for (var address, listener) in listeners {
            AudioObjectRemovePropertyListenerBlock(system, &address, .main, listener)
        }
        listeners = []
    }

    deinit { stopObserving() }

    private func property(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = property(selector)
        let size = MemoryLayout<T>.size
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<T>.alignment)
        defer { buffer.deallocate() }
        var count = UInt32(size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &count, buffer) == noErr, count == size else { return nil }
        return buffer.load(as: T.self)
    }

    private func name(_ device: AudioDeviceID) -> String {
        var address = property(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              let value else { return "Unknown device" }
        // kAudioObjectPropertyName transfers ownership to the caller.
        return value.takeRetainedValue() as String
    }

    private func deviceIDs() -> [AudioDeviceID] {
        var address = property(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !devices.isEmpty else { return [] }
        let status = devices.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }
        return status == noErr ? Array(devices.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size)) : []
    }

    private func channels(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        guard device != 0 else { return 0 }
        var address = property(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
