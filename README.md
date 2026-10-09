# TN3270-Mac

A native macOS TN3270 terminal emulator for connecting to IBM z/OS systems.

## Features

- **TN3270E** (RFC 2355) with device-type/LU negotiation, BIND-IMAGE, RESPONSES and
  SYSREQ functions, with automatic fallback to traditional **TN3270** (RFC 1576/1646).
- **SSL/TLS** via Network.framework — TLS 1.3 is the default minimum version
  (TLS 1.2 can be selected for older hosts), with optional certificate verification
  bypass for self-signed / private CA certificates.
- 3270 data stream: Write, Erase/Write, Erase/Write Alternate, Read Buffer, Read
  Modified (All), Erase All Unprotected, Write Structured Field (Read Partition
  Query, Erase/Reset, Outbound 3270DS) and all orders (SF, SFE, SBA, SA, MF, IC,
  PT, RA, EUA, GE), extended colors and highlighting.
- Terminal models 2 (24×80), 3 (32×80), 4 (43×80) and 5 (27×132).
- EBCDIC code pages 037, 273, 277, 278, 280, 284, 285, 297, 500, 1047 and the
  Euro variants 1140–1148.
- **Connection Options** window (Connection ▸ Connection Options…, ⇧⌘,): host /
  IP address, port, EBCDIC code page, terminal model, LU name, TN3270E and TLS.
- **Keyboard Options** window (Keyboard ▸ Keyboard Options…, ⌥⌘K): map any Mac
  key combination to a 3270 function (Enter, Clear, PF1–PF24, PA1–PA3, Attn,
  SysReq, Reset, Erase EOF, Insert, field tab, …). Mappings are saved
  automatically.

### Default key map

| Mac key | 3270 function |
| --- | --- |
| Return / keypad Enter | Enter |
| ⇧ Return | New Line |
| Tab / ⇧ Tab | Field Tab / Backtab |
| F1–F12 / ⇧ F1–F12 | PF1–PF12 / PF13–PF24 |
| Page Up / Page Down | PF7 / PF8 |
| Esc | Clear |
| ⌃R | Reset |
| ⌃C | Attention |
| ⌃S | System Request |
| ⌃1 / ⌃2 / ⌃3 | PA1 / PA2 / PA3 |
| End / ⌃E | Erase EOF |
| Help (Insert) / ⌃I | Insert mode |
| Home | Home |
| ⌫ / ⌦ | Backspace / Delete |

## Building and running

Requires macOS 13 or later and Xcode 15 (Swift 5.9) or later.

```sh
swift run TN3270Mac        # build and launch the app
swift test                 # run the unit tests
```

You can also open `Package.swift` in Xcode and run the `TN3270Mac` scheme.

## Project layout

- `Sources/TN3270Core` – platform independent protocol engine: EBCDIC code pages,
  telnet/TN3270E negotiation, 3270 data stream processing, screen buffer,
  key map and the Network.framework TLS transport.
- `Sources/TN3270Mac` – SwiftUI/AppKit macOS application (built on macOS only).
- `Tests/TN3270CoreTests` – XCTest unit tests (run on macOS and Linux).
