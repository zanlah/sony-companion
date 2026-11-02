# Sony Companion

A native macOS menu bar app for Sony WH-1000XM5 headphones, written in Swift and SwiftUI. macOS 14+, Apple Silicon or Intel. No third-party package dependencies.

## Run

Requires Xcode or the Apple command line developer tools with Swift 5.9+.

```sh
./scripts/build.sh --run
```

Connect your **WH-1000XM5** in macOS Bluetooth settings, then allow Sony Companion to use Bluetooth. A headphones icon appears in the menu bar; there is no Dock icon or main window. If the menu bar is full, macOS may hide it beside the notch.

The build produces `dist/Sony Companion.app`, signed locally with an ad-hoc signature. You can move it to Applications. This is a local development build, not a notarized distribution.

```sh
./scripts/build.sh --demo   # sample data, never opens Bluetooth
swift test                 # protocol tests; no headphones required
CONFIGURATION=release ./scripts/build.sh
```

Quit the running app before switching between real and demo mode. Demo is clearly labelled in the panel.

## Controls

- Battery percentage and active codec
- Noise cancelling, ambient sound, and off
- Ambient level and focus on voice
- EQ presets and five bands plus Clear Bass
- DSEE Extreme and Speak-to-Chat
- Automatic reconnect and a manual reconnect button

Controls stay disabled until their settings have been reported by the headphones. Changes are read back rather than assumed successful. Sliders send on release. Only the Sony control channel is closed on reconnect or quit; the app does not intentionally disconnect Bluetooth audio.

## Current scope

Targets **WH-1000XM5 over-ear headphones**, not WF earbuds or other Sony models. Actual hardware validation is still needed. Firmware updates, adaptive location/activity modes, global shortcuts, login startup, and multipoint device switching are not implemented.

If controls cannot connect, check System Settings → Privacy & Security → Bluetooth. Try quitting other Sony companion apps, then use the reconnect button. Pairing and the initial audio connection are handled in macOS settings.

## Development

- `Sources/SonyProtocol`: stream framing, checksum, stop-and-wait ACK session, commands, and confirmed headset state
- `Sources/SonyCompanion`: IOBluetooth RFCOMM transport and SwiftUI menu bar panel
- `Tests/SonyProtocolTests`: captured wire frames, malformed streams, ACK sequencing, timeout recovery, and command/state checks
- `scripts/build.sh`: SwiftPM build, app bundle, and local signing

The session retries an unanswered command twice, then reconnects to establish a fresh sequence. Device discovery is limited to paired WH-1000XM5s; no nearby-device scan is performed. The app uses no network services.

## Attribution

Independent project, not affiliated with Sony. The protocol implementation was informed by and partially adapted from [aecca/sound-connect](https://github.com/aecca/sound-connect), including its WH-1000XM5 wire fixtures. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
