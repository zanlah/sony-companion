import XCTest
@testable import SonyProtocol

final class ProtocolTests: XCTestCase {
    // Captured WH-1000XM5 frames from aecca/sound-connect, firmware 2.4.1.
    func testCapturedRequests() {
        XCTAssertEqual(Frame(sequence: 0, payload: [0, 0]).encoded,
                       [0x3e, 0x0c, 0, 0, 0, 0, 2, 0, 0, 0x0e, 0x3c])
        XCTAssertEqual(Frame(sequence: 1, payload: [0x66, 0x17]).encoded,
                       [0x3e, 0x0c, 1, 0, 0, 0, 2, 0x66, 0x17, 0x8c, 0x3c])
    }

    func testEscapedFragmentedStreamAndNoiseRecovery() {
        let frame = Frame(sequence: 1, payload: [0x3c, 0x3d, 0x3e])
        var reader = FrameReader()
        XCTAssertEqual(reader.receive([7, 8, 0x3e, 0, 0] + frame.encoded.prefix(5)), [])
        XCTAssertEqual(reader.receive(Array(frame.encoded.dropFirst(5))), [frame])
        XCTAssertEqual(reader.receive(frame.encoded + frame.encoded), [frame, frame])
    }

    func testCorruptionAndMalformedFramesAreRejected() {
        var corrupt = Frame(sequence: 0, payload: [0x22, 0]).encoded
        corrupt[8] ^= 1
        var reader = FrameReader()
        XCTAssertEqual(reader.receive(corrupt), [])
        XCTAssertEqual(reader.receive([0x3e, 0x3d, 0x3c]), [])
        // Valid checksum, invalid declared payload length.
        XCTAssertEqual(reader.receive([0x3e, 0x0c, 0, 0, 0, 0, 1, 0x0d, 0x3c]), [])
        XCTAssertEqual(reader.receive([0x3e] + Array(repeating: 0, count: 9000)), [])
        let good = Frame(sequence: 0, payload: [0x22, 0])
        XCTAssertEqual(reader.receive(good.encoded), [good])
    }

    func testACKSequencingAndIndependentNotifications() {
        var session = Session()
        let initial = session.enqueue([0, 0], now: 0)
        XCTAssertEqual(initial, [Frame(sequence: 0, payload: [0, 0]).encoded])
        XCTAssertEqual(session.enqueue([0x22, 0], now: 0), [])
        let notification = Frame(sequence: 0, payload: [0x23, 0, 82, 0])
        let received = session.receive(notification.encoded, now: 0.1)
        XCTAssertEqual(received.replies, [notification.payload])
        XCTAssertEqual(received.writes, [Frame(kind: 1, sequence: 1, payload: []).encoded])
        // A stale ACK cannot advance the queue.
        XCTAssertEqual(session.receive(Frame(kind: 1, sequence: 0, payload: []).encoded, now: 0.2).writes, [])
        let next = session.receive(Frame(kind: 1, sequence: 1, payload: []).encoded, now: 0.3)
        XCTAssertEqual(next.writes, [Frame(sequence: 1, payload: [0x22, 0]).encoded])
    }

    func testTimeoutRetriesSameSequenceThenFailsClosed() {
        var session = Session()
        let initial = session.enqueue([0, 0], now: 0)
        _ = session.enqueue([0x22, 0], now: 0)
        XCTAssertEqual(session.tick(now: 0.9), [])
        XCTAssertEqual(session.tick(now: 1), initial)
        XCTAssertEqual(session.tick(now: 2), initial)
        XCTAssertEqual(session.tick(now: 3), [])
        XCTAssertTrue(session.failed)
        XCTAssertEqual(session.enqueue([0x66, 0x17], now: 4), [])
    }

    func testCoalescesUnsentSliderChanges() {
        var session = Session()
        _ = session.enqueue([0, 0], now: 0)
        for level in [5, 10, 15] {
            _ = session.enqueue(NoiseState(mode: .ambient, level: level, focus: false).command, now: 0)
        }
        let output = session.receive(Frame(kind: 1, sequence: 1, payload: []).encoded, now: 0.1)
        XCTAssertEqual(output.writes, [Frame(sequence: 1, payload: [0x68, 0x17, 1, 1, 1, 0, 15]).encoded])
    }

    func testStateUsesConfirmedXM5RepliesAndIgnoresTruncation() {
        var state = HeadphoneState()
        XCTAssertNil(state.noise)
        state.apply([1, 0, 3, 0, 0x20, 0x16, 0, 0])
        XCTAssertTrue(state.ready)
        state.apply([0x23, 0, 82, 0]); XCTAssertEqual(state.battery, 82)
        state.apply([0x67, 0x17, 1, 1, 1, 1, 12])
        XCTAssertEqual(state.noise, NoiseState(mode: .ambient, level: 12, focus: true))
        state.apply([0xf7, 0x0c, 0]); XCTAssertEqual(state.speakToChat, true)
        state.apply([0x57, 0, 0xa0, 6, 10, 0, 20, 11, 9, 10])
        XCTAssertEqual(state.eqValues, [0, -10, 10, 1, -1, 0])
        for opcode: UInt8 in [0x23, 0x67, 0x57, 0xe7, 0xf7, 0x13] {
            state.apply([opcode]); state.apply([opcode, 0])
        }
        XCTAssertEqual(state.battery, 82)
        state.apply([0x23, 0, 255, 0]); XCTAssertEqual(state.battery, 82)
    }

    func testCommandsPreserveOtherNoiseSettingsAndClampEQ() {
        XCTAssertEqual(NoiseState(mode: .cancelling, level: 12, focus: true).command,
                       [0x68, 0x17, 1, 1, 0, 1, 12])
        XCTAssertEqual(HeadphoneState.manualEQ([-100, 0, 100, 1, -1, 0]),
                       [0x58, 0, 0xa0, 6, 0, 10, 20, 11, 9, 10])
        XCTAssertNil(HeadphoneState.manualEQ([0]))
    }
}
