import Foundation

// Framing and captured fixtures adapted from aecca/sound-connect (MIT).
// See THIRD_PARTY_NOTICES.md.
public struct Frame: Equatable {
    public let kind: UInt8
    public let sequence: UInt8
    public let payload: [UInt8]

    public init(kind: UInt8 = 0x0c, sequence: UInt8, payload: [UInt8]) {
        self.kind = kind
        self.sequence = sequence
        self.payload = payload
    }

    public var encoded: [UInt8] {
        let length = UInt32(payload.count)
        var body = [kind, sequence] + (0..<4).reversed().map { UInt8(truncatingIfNeeded: length >> ($0 * 8)) } + payload
        body.append(body.reduce(0, &+))
        return [0x3e] + body.flatMap { byte -> [UInt8] in
            [0x3c, 0x3d, 0x3e].contains(byte) ? [0x3d, byte & 0xef] : [byte]
        } + [0x3c]
    }
}

public struct FrameReader {
    private var body: [UInt8] = []
    private var reading = false
    public init() {}

    public mutating func receive(_ bytes: [UInt8]) -> [Frame] {
        var frames: [Frame] = []
        for byte in bytes {
            if byte == 0x3e { body = []; reading = true }
            else if byte == 0x3c {
                if reading, let frame = decode() { frames.append(frame) }
                body = []; reading = false
            } else if reading {
                body.append(byte)
                // Bound memory if a corrupt stream never supplies an end marker.
                if body.count > 8192 { body = []; reading = false }
            }
        }
        return frames
    }

    private func decode() -> Frame? {
        var bytes: [UInt8] = []
        var escaped = false
        for byte in body {
            if escaped {
                guard [0x2c, 0x2d, 0x2e].contains(byte) else { return nil }
                bytes.append(byte | 0x10); escaped = false
            } else if byte == 0x3d { escaped = true }
            else { bytes.append(byte) }
        }
        guard !escaped, bytes.count >= 7,
              bytes.dropLast().reduce(0, &+) == bytes.last else { return nil }
        let length = bytes[2..<6].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length == bytes.count - 7 else { return nil }
        return Frame(kind: bytes[0], sequence: bytes[1], payload: Array(bytes[6..<bytes.count - 1]))
    }
}

/// One request in flight, ACK sequencing, and bounded retries. A missing ACK
/// terminates the session instead of advancing with an uncertain sequence.
public struct Session {
    private var reader = FrameReader()
    private var sequence: UInt8 = 0
    private struct Command {
        var kind: UInt8
        var payload: [UInt8]
    }
    private var pending: [Command] = []
    private var inFlight: Command?
    private var sentAt: TimeInterval = 0
    private var retries = 0
    public private(set) var failed = false
    public init() {}

    public mutating func enqueue(_ payload: [UInt8], kind: UInt8 = 0x0c, now: TimeInterval) -> [[UInt8]] {
        guard !failed else { return [] }
        // Slider changes replace an unsent command for the same setting.
        if kind == 0x0c, [0x68, 0x58].contains(payload.first) {
            pending.removeAll { $0.kind == kind && Array($0.payload.prefix(2)) == Array(payload.prefix(2)) }
        }
        pending.append(Command(kind: kind, payload: payload))
        return next(now: now)
    }

    public mutating func receive(_ bytes: [UInt8], now: TimeInterval) -> (writes: [[UInt8]], replies: [[UInt8]], table2Replies: [[UInt8]]) {
        guard !failed else { return ([], [], []) }
        var writes: [[UInt8]] = []
        var replies: [[UInt8]] = []
        var table2Replies: [[UInt8]] = []
        for frame in reader.receive(bytes) {
            if frame.kind == 1 {
                if inFlight != nil, frame.sequence == (sequence ^ 1), frame.payload.isEmpty {
                    sequence = frame.sequence; inFlight = nil
                }
            } else if frame.sequence <= 1 {
                writes.append(Frame(kind: 1, sequence: frame.sequence ^ 1, payload: []).encoded)
                if frame.kind == 0x0c { replies.append(frame.payload) }
                if frame.kind == 0x0e { table2Replies.append(frame.payload) }
            }
        }
        writes += next(now: now)
        return (writes, replies, table2Replies)
    }

    public mutating func tick(now: TimeInterval) -> [[UInt8]] {
        guard let inFlight, now - sentAt >= 1 else { return [] }
        guard retries < 2 else { failed = true; pending = []; return [] }
        retries += 1; sentAt = now
        return [Frame(kind: inFlight.kind, sequence: sequence, payload: inFlight.payload).encoded]
    }

    private mutating func next(now: TimeInterval) -> [[UInt8]] {
        guard inFlight == nil, !pending.isEmpty, !failed else { return [] }
        let command = pending.removeFirst()
        inFlight = command; sentAt = now; retries = 0
        return [Frame(kind: command.kind, sequence: sequence, payload: command.payload).encoded]
    }
}
