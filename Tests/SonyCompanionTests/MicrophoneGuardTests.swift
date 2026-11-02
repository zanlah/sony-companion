import XCTest
import CoreAudio
@testable import SonyCompanion

final class MicrophoneGuardTests: XCTestCase {
    private let mac = AudioInput(id: 1, name: "MacBook Microphone", builtIn: true)
    private let sony = AudioInput(id: 2, name: "WH-1000XM5", builtIn: false)

    private func makeGuard(_ routing: FakeRouting) -> MicrophoneGuard {
        let suite = "SonyCompanionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return MicrophoneGuard(routing: routing, defaults: defaults)
    }

    func testSelectsBuiltInInputWhenSonyIsOutputAndConfirmsActualInput() {
        let routing = FakeRouting(inputs: [sony, mac], selected: sony.id)
        let model = makeGuard(routing)
        model.refresh()
        XCTAssertEqual(routing.writes, [mac.id])
        XCTAssertEqual(model.inputName, mac.name)
        XCTAssertEqual(model.outputDescription, "48 kHz · Stereo")
        model.refresh()
        XCTAssertEqual(routing.writes, [mac.id], "Already selected input must not be repeatedly set")
    }

    func testDoesNotTouchOtherOutputDevicesOrDisabledGuard() {
        let routing = FakeRouting(inputs: [sony, mac], selected: sony.id)
        routing.snapshot.sonyOutput = false
        let model = makeGuard(routing)
        model.refresh()
        XCTAssertTrue(routing.writes.isEmpty)
        routing.snapshot.sonyOutput = true
        model.setEnabled(false)
        XCTAssertTrue(routing.writes.isEmpty)
        XCTAssertEqual(model.inputName, sony.name)
    }

    func testNoBuiltInMicAndFailedSetAreReportedWithoutFalseConfirmation() {
        let routing = FakeRouting(inputs: [sony], selected: sony.id)
        let model = makeGuard(routing)
        model.refresh()
        XCTAssertTrue(routing.writes.isEmpty)
        XCTAssertTrue(model.message.contains("No built-in microphone"))
        routing.snapshot.inputs.append(mac)
        routing.error = -1
        model.refresh()
        XCTAssertEqual(model.inputName, sony.name)
        XCTAssertTrue(model.message.contains("Could not select"))
    }

    func testReportsLowBandwidthEvenWhenMacMicrophoneIsSelected() {
        let routing = FakeRouting(inputs: [mac, sony], selected: mac.id)
        routing.snapshot.outputRate = 16000
        routing.snapshot.outputChannels = 1
        let model = makeGuard(routing)
        model.refresh()
        XCTAssertEqual(model.inputName, mac.name)
        XCTAssertEqual(model.outputDescription, "16 kHz · Mono")
        XCTAssertTrue(model.message.contains("Low-bandwidth"))
        XCTAssertTrue(routing.writes.isEmpty)
    }

    func testReassertsInputOnRouteChangeAndStopsObserving() {
        let routing = FakeRouting(inputs: [mac, sony], selected: mac.id)
        let model = makeGuard(routing)
        model.start()
        routing.snapshot.defaultInput = sony.id
        routing.changed?()
        XCTAssertEqual(routing.writes, [mac.id])
        model.stop()
        XCTAssertNil(routing.changed)
    }

    func testDemoNeverTouchesSystemAudioOrStoresPreference() {
        let routing = FakeRouting(inputs: [mac, sony], selected: sony.id)
        let suite = "SonyCompanionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = MicrophoneGuard(routing: routing, defaults: defaults, demo: true)
        model.start(); model.setEnabled(false); model.refresh(); model.stop()
        XCTAssertTrue(routing.writes.isEmpty)
        XCTAssertEqual(routing.reads, 0)
        XCTAssertNil(defaults.object(forKey: "useMacMicrophone"))
    }

    func testOutputResetReturnsToHeadphonesAndRestoresOnStop() {
        let routing = FakeRouting(inputs: [mac, sony], selected: mac.id)
        let model = makeGuard(routing)
        model.resetOutput()
        XCTAssertEqual(routing.outputWrites, [10])
        XCTAssertTrue(model.resettingOutput)
        model.stop() // Closing the app mid-reset must not leave speakers selected.
        XCTAssertEqual(routing.outputWrites, [10, 20])
        XCTAssertFalse(model.resettingOutput)
    }

    func testOutputResetCompletesWithoutClosingTheApp() {
        let routing = FakeRouting(inputs: [mac, sony], selected: mac.id)
        let model = makeGuard(routing)
        model.resetOutput()
        let restored = expectation(description: "Headphone output restored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            XCTAssertEqual(routing.outputWrites, [10, 20])
            XCTAssertFalse(model.resettingOutput)
            restored.fulfill()
        }
        wait(for: [restored], timeout: 2)
    }

    func testOutputResetRespectsAnOutputSelectedByTheUser() {
        let routing = FakeRouting(inputs: [mac, sony], selected: mac.id)
        let model = makeGuard(routing)
        model.resetOutput()
        routing.snapshot.outputID = 99
        model.stop()
        XCTAssertEqual(routing.outputWrites, [10])
        XCTAssertEqual(routing.snapshot.outputID, 99)
    }

    func testCanReadLiveAudioRouteWithoutOpeningCapture() {
        let routing = CoreAudioRouting()
        let snapshot = routing.route()
        XCTAssertTrue(snapshot.inputs.allSatisfy { $0.id != 0 && !$0.name.isEmpty })
        if let rate = snapshot.outputRate { XCTAssertGreaterThan(rate, 0) }
    }
}

private final class FakeRouting: AudioRouting {
    var snapshot: AudioRoute
    var writes: [AudioDeviceID] = []
    var reads = 0
    var outputWrites: [AudioDeviceID] = []
    var error: OSStatus = noErr
    var changed: (() -> Void)?
    init(inputs: [AudioInput], selected: AudioDeviceID) {
        snapshot = AudioRoute(inputs: inputs, defaultInput: selected, sonyOutput: true, outputRate: 48000, outputChannels: 2, outputID: 20, builtInOutputID: 10)
    }
    func route() -> AudioRoute { reads += 1; return snapshot }
    func setInput(_ id: AudioDeviceID) -> OSStatus {
        writes.append(id)
        if error == noErr { snapshot.defaultInput = id }
        return error
    }
    func setOutput(_ id: AudioDeviceID) -> OSStatus {
        outputWrites.append(id); snapshot.outputID = id; snapshot.sonyOutput = id == 20
        return noErr
    }
    func observe(_ changed: @escaping () -> Void) { self.changed = changed }
    func stopObserving() { changed = nil }
}
