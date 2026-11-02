import AppKit
import IOBluetooth
import SonyProtocol

/// IOBluetooth callbacks and timers run on the main run loop.
final class HeadphoneController: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate {
    let microphone = MicrophoneGuard(demo: ProcessInfo.processInfo.arguments.contains("--demo"))
    @Published private(set) var state = HeadphoneState()
    @Published private(set) var status = "Looking for your XM5s"
    @Published private(set) var connected = false
    @Published private(set) var deviceName = "WH-1000XM5"
    @Published private(set) var notice: String?
    @Published private(set) var demo = false
    @Published private(set) var playbackDevices: [PlaybackDevice]?
    @Published private(set) var sourceStatus = "Reading connected devices…"
    @Published private(set) var switchingTo: String?
    private var sourceLayout: DeviceListLayout?
    private var lastSourceRefresh: TimeInterval = 0
    private var switchDeadline: TimeInterval = 0
    private var channel: IOBluetoothRFCOMMChannel?
    private var session = Session()
    private var timer: Timer?
    private var deadline: TimeInterval = 0
    private var nextAttempt: TimeInterval = 0
    private var lastRefresh: TimeInterval = 0
    private var stopped = false
    private var handshakeRequested = false
    private var queryPending = false
    private var queryDeadline: TimeInterval = 0
    private let service: IOBluetoothSDPUUID = {
        var uuid = UUID(uuidString: "956C7B26-D49A-4BA8-B03F-B17D393CB6E2")!.uuid
        return withUnsafeBytes(of: &uuid) { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
    }()
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start() {
        microphone.start()
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            demo = true; connected = true; status = "Demo · sample data"
            for reply: [UInt8] in [[1, 0, 3, 0, 0x20, 0x16, 0, 0], [0x23, 0, 82, 0],
                                  [0x67, 0x17, 1, 1, 0, 0, 12], [0x57, 0, 0, 6, 10, 10, 10, 10, 10, 10],
                                  [0xe7, 1, 0], [0xf7, 0x0c, 1], [0x13, 2, 2]] { state.apply(reply) }
            sourceLayout = .classic
            handleSourceReply([0x39, 0, 2] + Array("11:22:33:44:55:66".utf8) + [1, 7] + Array("MacBook".utf8)
                              + Array("AA:BB:CC:DD:EE:FF".utf8) + [2, 6] + Array("iPhone".utf8) + [1])
            return
        }
        timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        attempt()
    }

    func stop() {
        microphone.stop()
        stopped = true; timer?.invalidate(); timer = nil
        tearDown()
    }

    func retry() {
        guard !demo else { return }
        notice = nil; tearDown(); nextAttempt = 0; attempt()
    }

    func refresh() {
        guard connected, state.ready, !demo else { return }
        for query in HeadphoneState.queries { send(query) }
        lastRefresh = now
    }

    func refreshSources() {
        guard let sourceLayout, connected, state.ready, !demo else { return }
        send(sourceLayout.query, kind: 0x0e)
        lastSourceRefresh = now
    }

    func playFrom(_ device: PlaybackDevice) {
        guard switchingTo == nil, sourceLayout != nil,
              playbackDevices?.contains(where: { $0.id == device.id && !$0.playing }) == true,
              let command = PlaybackSources.switchCommand(address: device.id) else { return }
        if demo {
            playbackDevices = playbackDevices?.map { PlaybackDevice(id: $0.id, name: $0.name, playing: $0.id == device.id) }
            return
        }
        guard connected, state.ready else { return }
        switchingTo = device.id; switchDeadline = now + 6
        sourceStatus = "Switching to \(device.name)…"
        send(command, kind: 0x0e)
        refreshSources()
    }

    private func handleSourceReply(_ payload: [UInt8]) {
        guard let reply = PlaybackSources.parse(payload) else { return }
        switch reply {
        case .capabilities(let layout):
            sourceLayout = layout
            sourceStatus = layout == nil ? "Source switching is unavailable on these headphones." : "Reading connected devices…"
            refreshSources()
        case .devices(let devices):
            playbackDevices = devices
            if let target = switchingTo {
                if devices.contains(where: { $0.id == target && $0.playing }) {
                    switchingTo = nil; sourceStatus = "Audio source switched."
                } else if !devices.contains(where: { $0.id == target }) {
                    switchingTo = nil; sourceStatus = "The selected device disconnected."
                }
            } else {
                sourceStatus = devices.count < 2 ? "Connect both devices to switch between them." : "Choose which device you hear."
            }
        case .switchAcknowledged:
            // The acknowledgement does not guarantee success, e.g. during a call.
            refreshSources()
        }
    }

    func setNoise(mode: NoiseMode? = nil, level: Int? = nil, focus: Bool? = nil) {
        guard var noise = state.noise else { return }
        if let mode { noise.mode = mode }
        if let level { noise.level = level }
        if let focus { noise.focus = focus }
        if demo { state.noise = noise; return }
        send(noise.command); send([0x66, 0x17])
    }

    func setPreset(_ preset: EQPreset) {
        guard state.preset != nil else { return }
        if demo { state.preset = preset.rawValue; return }
        send([0x58, 0, preset.rawValue, 0]); send([0x56, 0])
    }

    func setEQ(index: Int, value: Int) {
        guard var values = state.eqValues, values.indices.contains(index) else { return }
        values[index] = value
        guard let command = HeadphoneState.manualEQ(values) else { return }
        if demo { state.eqValues = values; state.preset = EQPreset.manual.rawValue; return }
        send(command); send([0x56, 0])
    }

    func setDSEE(_ on: Bool) {
        if demo { state.dsee = on; return }
        send([0xe8, 1, on ? 1 : 0]); send([0xe6, 1])
    }

    func setChat(_ on: Bool) {
        if demo { state.speakToChat = on; return }
        send([0xf8, 0x0c, on ? 0 : 1, 1]); send([0xf6, 0x0c])
    }

    private func tick() {
        guard !stopped else { return }
        if channel == nil {
            if queryPending, now >= queryDeadline { queryPending = false }
            if now >= nextAttempt { attempt() }
            return
        }
        if !connected, now >= deadline { fail("Opening the Bluetooth control channel timed out."); return }
        if connected {
            write(session.tick(now: now))
            if session.failed { fail("The headphones stopped responding. Retrying…"); return }
            if !state.ready, now >= deadline { fail("The headphones did not finish the handshake."); return }
            if state.ready, now - lastRefresh >= 60 { refresh() }
            if state.ready, sourceLayout != nil, now - lastSourceRefresh >= (switchingTo == nil ? 5 : 1) { refreshSources() }
            if switchingTo != nil, now >= switchDeadline {
                switchingTo = nil
                sourceStatus = "Switch not confirmed. Pause playback or end the call, then try again."
            }
        }
    }

    private func attempt() {
        guard channel == nil, !stopped else { return }
        nextAttempt = now + 5
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let candidates = devices.filter { ($0.name ?? "").uppercased().contains("WH-1000XM5") }
        guard let device = candidates.first(where: { $0.isConnected() }) else {
            status = candidates.isEmpty ? "Pair your XM5s in Bluetooth settings" : "Connect your XM5s to this Mac"
            return
        }
        deviceName = device.nameOrAddress
        guard let record = device.getServiceRecord(for: service) else {
            status = "Discovering headphone controls…"
            if !queryPending {
                queryPending = true; queryDeadline = now + 10
                if device.performSDPQuery(self, uuids: [service]) != kIOReturnSuccess { queryPending = false }
            }
            return
        }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
            notice = "Sony control service has no serial channel."; return
        }
        session = Session(); state = HeadphoneState(); handshakeRequested = false
        status = "Connecting to \(deviceName)…"
        deadline = now + 15
        var opened: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
        if result == kIOReturnSuccess, let opened { channel = opened }
        else { opened?.close(); notice = "Could not open Sony controls (\(result))." }
    }

    @objc private func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        queryPending = false
        nextAttempt = now + 0.5
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard rfcommChannel === channel else { return }
        guard error == kIOReturnSuccess else { fail("Bluetooth control connection failed (\(error))."); return }
        connected = true; status = "Reading headphone settings…"; notice = nil
        deadline = now + 10
        write(session.enqueue([0, 0], now: now))
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length: Int) {
        guard rfcommChannel === channel, let pointer, length > 0 else { return }
        let bytes = Array(UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: length))
        let output = session.receive(bytes, now: now)
        write(output.writes)
        for reply in output.replies { state.apply(reply) }
        for reply in output.table2Replies { handleSourceReply(reply) }
        if state.unsupported { fail("This app supports the WH-1000XM5 v2 protocol."); return }
        if state.ready, !handshakeRequested {
            handshakeRequested = true; status = "Connected"; refresh()
            if state.table2Supported { send(PlaybackSources.capabilityQuery, kind: 0x0e) }
            else { sourceStatus = "Source switching is unavailable on these headphones." }
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard rfcommChannel === channel else { return }
        tearDown(); status = "Headphones disconnected"; nextAttempt = now + 2
    }

    private func send(_ payload: [UInt8], kind: UInt8 = 0x0c) {
        guard connected, state.ready, !demo else { return }
        write(session.enqueue(payload, kind: kind, now: now))
    }

    private func write(_ frames: [[UInt8]]) {
        guard let channel else { return }
        for var frame in frames {
            let result = frame.withUnsafeMutableBytes { channel.writeSync($0.baseAddress, length: UInt16($0.count)) }
            if result != kIOReturnSuccess { fail("Sending a headphone command failed (\(result))."); return }
        }
    }

    private func fail(_ message: String) {
        tearDown(); notice = message; status = "Waiting to reconnect"; nextAttempt = now + 5
    }

    private func tearDown() {
        let old = channel; channel = nil; old?.close()
        connected = false; state = HeadphoneState(); session = Session(); queryPending = false
        sourceLayout = nil; playbackDevices = nil; switchingTo = nil
        sourceStatus = "Reading connected devices…"; lastSourceRefresh = 0
    }
}
