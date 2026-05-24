# Libre 3 sample iOS client

Stock-iPhone Swift app that drives the Libre 3 BLE handshake and NFC
takeover, delegating native crypto over HTTP to the paired Android
shim at
[poml88/libre3-auth-android-server](https://github.com/poml88/libre3-auth-android-server).

## Project status

- To the best of my knowledge, this was the first publicly available open-source solution for Libre 3 BLE connectivity on iOS at the time of writing.
- It is not fully offline, because this app still performs an HTTP request to the paired Android shim during each new BLE handshake.
- In that sense, it is more accurate to describe this approach as “99% offline” rather than 100% offline.
- This implementation may already be superseded by newer work toward a fully offline solution, including the Swift package `LibreCRkit`, which is being developed by other contributors.

## Disclaimer

This is a personal hobby project for research and interoperability. It
is **not** a medical device and is **not** affiliated with, endorsed by,
or connected to Abbott Laboratories, FreeStyle Libre, or any of their
subsidiaries or partners. All trademarks are the property of their
respective owners.

The code is provided **"as is", without warranty of any kind**, express
or implied. In no event shall the authors or contributors be liable for
any claim, damages, or other liability — including but not limited to
incorrect glucose readings, missed alarms, sensor damage, account
lockout, or any direct, indirect, incidental, or consequential loss —
arising from the use of, or inability to use, this software.

**Do not use the output of this software to make medical or treatment
decisions.** Always rely on a regulator-approved reader or the
manufacturer's official application for clinical use.

Use at your own risk.

## Credits

Built on two prior open-source Libre 3 projects:

- **[Juggluco](https://github.com/j-kaltes/Juggluco)** — the v1 identity
  constants in `Libre3ResearchMaterial.swift` come from Juggluco's
  `ECDHCrypto.java`. The Android shim this app talks to loads a native
  library shipped in Juggluco's APK.
- **[DiaBLE](https://github.com/gui-dos/DiaBLE)** — the BLE state
  machine, NFC takeover commands, and packet AES-CCM framing in this
  app mirror DiaBLE's `Libre3.swift`.

## Setup

1. Stand up the Android shim (see its README).
2. Open `libre3AndroidServer.xcodeproj` in Xcode, set your signing team,
   run on a real iPhone with NFC.
3. In the app: enter the shim's base URL (e.g. `http://192.168.1.42:8080`)
   and tap **Apply and ping /health** — expect `loaderReady: true`.
4. NFC-tap a sensor already activated by Abbott's official Libre 3 app
   (this client only does **takeover**, not first-time activation).
