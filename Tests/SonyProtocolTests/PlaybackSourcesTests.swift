import XCTest
@testable import SonyProtocol

final class PlaybackSourcesTests: XCTestCase {
    private func list(layout: DeviceListLayout, active: UInt8 = 2) -> [UInt8] {
        var payload: [UInt8] = [0x37, layout.rawValue, 3]
        for (address, slot, name): (String, UInt8, String) in [
            ("11:22:33:44:55:66", 1, "MacBook"),
            ("AA:BB:CC:DD:EE:FF", 2, "Telefon 📱"),
            ("00:11:22:33:44:55", 0, "Old laptop")
        ] {
            payload += Array(address.utf8) + [slot]
            if layout == .withClass { payload += [0x5a, 2, 0x0c] }
            let nameBytes = Array(name.utf8)
            payload += [UInt8(nameBytes.count)] + nameBytes
        }
        return payload + [active]
    }

    func testCapabilitiesChooseSupportedLayout() {
        XCTAssertEqual(PlaybackSources.parse([7, 0, 2, 0x30, 0xff, 0x32, 4]), .capabilities(.withClass))
        XCTAssertEqual(PlaybackSources.parse([7, 0, 1, 0x30, 0xff]), .capabilities(.classic))
        XCTAssertEqual(PlaybackSources.parse([7, 0, 1, 0x42, 0xff]), .capabilities(nil))
        XCTAssertNil(PlaybackSources.parse([7, 0, 2, 0x32, 4]))
    }

    func testBothLayoutsShowOnlyConnectedDevicesAndActiveSlot() {
        let expected: SourceReply = .devices([
            PlaybackDevice(id: "11:22:33:44:55:66", name: "MacBook", playing: false),
            PlaybackDevice(id: "AA:BB:CC:DD:EE:FF", name: "Telefon 📱", playing: true)
        ])
        for layout in [DeviceListLayout.classic, .withClass] {
            XCTAssertEqual(PlaybackSources.parse(list(layout: layout)), expected)
            var notification = list(layout: layout)
            notification[0] = 0x39
            XCTAssertEqual(PlaybackSources.parse(notification), expected)
            if case .devices(let devices) = PlaybackSources.parse(list(layout: layout, active: 0)) {
                XCTAssertFalse(devices.contains(where: \.playing))
            } else { XCTFail("Could not parse inactive source list") }
        }
        XCTAssertEqual(PlaybackSources.parse([0x39, 0, 0, 0]), .devices([]))
    }

    func testRejectsEveryTruncatedListAndMalformedAddress() {
        for layout in [DeviceListLayout.classic, .withClass] {
            let bytes = list(layout: layout)
            for end in 0..<bytes.count { XCTAssertNil(PlaybackSources.parse(Array(bytes.prefix(end)))) }
            var invalid = bytes; invalid[3] = 0xff
            XCTAssertNil(PlaybackSources.parse(invalid))
            XCTAssertNil(PlaybackSources.parse(bytes + [0]))
        }
        XCTAssertNil(PlaybackSources.parse([0x37, 3, 0, 0]))
    }

    func testSourceSwitchAddressIsValidatedAndMarkerIsEscaped() {
        let command = PlaybackSources.switchCommand(address: "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(command, [0x3c, 1] + Array("AA:BB:CC:DD:EE:FF".utf8))
        XCTAssertNil(PlaybackSources.switchCommand(address: "AA:BB"))
        XCTAssertNil(PlaybackSources.switchCommand(address: "GG:BB:CC:DD:EE:FF"))
        XCTAssertNil(PlaybackSources.switchCommand(address: "AA-BB-CC-DD-EE-FF"))
        let frame = Frame(kind: 0x0e, sequence: 0, payload: command!)
        XCTAssertTrue(frame.encoded.contains(0x3d))
        var reader = FrameReader()
        XCTAssertEqual(reader.receive(frame.encoded), [frame])
    }

    func testCommandTableSurvivesQueueAndRetries() {
        var session = Session()
        _ = session.enqueue([0x22, 0], now: 0)
        XCTAssertEqual(session.enqueue([0x36, 2], kind: 0x0e, now: 0), [])
        let output = session.receive(Frame(kind: 1, sequence: 1, payload: []).encoded, now: 0.1)
        let expected = Frame(kind: 0x0e, sequence: 1, payload: [0x36, 2]).encoded
        XCTAssertEqual(output.writes, [expected])
        XCTAssertEqual(session.tick(now: 1.2), [expected])
    }

    func testTableTwoRepliesCannotAffectBaseSettings() {
        var session = Session()
        let payload: [UInt8] = [0xf7, 0x0c, 0]
        let result = session.receive(Frame(kind: 0x0e, sequence: 1, payload: payload).encoded, now: 0)
        XCTAssertEqual(result.replies, [])
        XCTAssertEqual(result.table2Replies, [payload])
        XCTAssertEqual(result.writes, [Frame(kind: 1, sequence: 0, payload: []).encoded])
        XCTAssertNil(PlaybackSources.parse(payload))
        XCTAssertEqual(PlaybackSources.parse([0x3d, 1, 2]), .switchAcknowledged)
        var state = HeadphoneState()
        state.apply([1, 0, 3, 0, 0x20, 0x16, 0, 0])
        XCTAssertTrue(state.table2Supported)
        state.apply([1, 0, 3, 0, 0x20, 0x16, 0, 1])
        XCTAssertFalse(state.table2Supported)
    }
}
