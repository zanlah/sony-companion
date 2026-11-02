# Sony Companion

A native macOS menu bar app for Sony WH-1000XM5 headphones, written in Swift and SwiftUI. The panel uses an AppKit popover anchored to the menu bar icon and scrolls when expanded settings exceed the available screen height. macOS 14+, Apple Silicon or Intel. No third-party package dependencies.

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

- Audio source selection between devices connected through multipoint, with the active source reported by the headphones
- Battery percentage and active codec
- Noise cancelling, ambient sound, and off
- Ambient level and focus on voice
- EQ presets and five bands plus Clear Bass
- DSEE Extreme and Speak-to-Chat
- Keep the system input on the Mac microphone while XM5 is the output, with live input/output format and a manual output reset
- Automatic reconnect and a manual reconnect button

Controls stay disabled until their settings have been reported by the headphones. Changes are read back rather than assumed successful. Sliders send on release. Only the Sony control channel is closed on reconnect or quit; the app does not intentionally disconnect Bluetooth audio.

## Current scope

Targets **WH-1000XM5 over-ear headphones**, not WF earbuds or other Sony models. Actual hardware validation is still needed. Firmware updates, adaptive location/activity modes, global shortcuts and login startup are not implemented.

If controls cannot connect, check System Settings → Privacy & Security → Bluetooth. Try quitting other Sony companion apps, then use the reconnect button. Pairing and the initial audio connection are handled in macOS settings.

## Switching between phone and Mac

Enable the option to connect two devices simultaneously in Sony's mobile app, then connect both the phone and Mac to the headphones. The **Audio Source** section lists the devices the headphones report as connected. Choose a device in the **Play from** selector. Its selection updates only after the headphones confirm the source. Noise controls and all sound settings remain visible below the compact source selector.

The list refreshes every five seconds and can also be refreshed manually. While switching, the app checks for confirmation for up to six seconds. The command changes the headphones' selected source; it does not remotely press Play in a phone app. If needed, start playback on the selected device. During a call, the headphones may refuse a switch. The app then keeps the reported source and displays a message. Hardware verification of multipoint switching is still needed.

## Microphone and call audio quality

**Call Audio → Use Mac microphone** is on by default and remembered between launches. When the system output is WH-1000XM5 over Bluetooth, it keeps the built-in Mac microphone selected as the default input. Turning it off stops enforcement and leaves the currently selected input in place. It does not record audio or request microphone capture access.

Apps such as Zoom or Discord can select an input independently: choose the Mac microphone or System Default inside the calling app too. A phone call over multipoint can also keep the headphones in call mode. This app cannot block another process from directly opening the Sony microphone or force high-quality Bluetooth playback while that microphone is in use. See [Apple's explanation](https://support.apple.com/en-mide/102217).

The panel displays the actual system input and the output's nominal sample rate/channel count, and flags an output at 24 kHz or lower. This describes the CoreAudio format, not a definitive Bluetooth profile/codec measurement. If sound remains degraded after choosing the Mac mic, **Re-select headphone output** follows Apple's workaround: it briefly selects the Mac speakers and returns to the headphones. Playback can be audible through the speakers during that reset; it runs only when clicked. No automatic output switching occurs. If you select another output during the reset, your selection is respected.

## Development

- `Sources/SonyProtocol`: stream framing, checksum, stop-and-wait ACK session, commands, and confirmed headset state
- `Sources/SonyCompanion`: IOBluetooth RFCOMM transport and SwiftUI menu bar panel
- `Tests/SonyProtocolTests`: captured wire frames, malformed streams, ACK sequencing, timeout recovery, and command/state checks
- `scripts/build.sh`: SwiftPM build, app bundle, and local signing

The session retries an unanswered command twice, then reconnects to establish a fresh sequence. Device discovery is limited to paired WH-1000XM5s; no nearby-device scan is performed. The app uses no network services.

## Attribution

Independent project, not affiliated with Sony. The protocol implementation was informed by and partially adapted from [aecca/sound-connect](https://github.com/aecca/sound-connect), including its WH-1000XM5 wire fixtures. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
