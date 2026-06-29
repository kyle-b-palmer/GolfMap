# Apple Watch Companion

The **Golf Map Watch** app syncs with the iPhone app during an active round.

## Features

- Live hole, par, and total score
- `+` / `-` scoring (syncs back to iPhone)
- PREV / NEXT hole
- **GPS yardage to green** using the watch location and green coordinates from the phone

## How sync works

iPhone and Watch are separate devices, so they communicate with **WatchConnectivity**:

1. iPhone pushes round state when you start or update a round.
2. Watch stores the latest round locally and shows it immediately.
3. Watch score/hole changes are sent to the phone, written into the same shared round state the Live Activity uses, and Flutter picks them up via the existing `consumeWidgetChanges` flow.

Green latitude/longitude are sent from the phone whenever the hole changes. The watch computes yardage locally with `CLLocation`.

## Build & install

### iPhone only (`flutter run`)

The Watch app is **not** built during normal `flutter run` — you don't need the watchOS SDK installed on your Mac for day-to-day iPhone development.

```bash
flutter run -d <your-iphone>
```

### Apple Watch (optional)

1. In Xcode: **Settings → Platforms** (or Components) → install **watchOS 11.x**
2. Open `ios/Runner.xcworkspace`
3. Select the **GolfMapWatch** scheme and your paired watch as the destination
4. Build & run (install iPhone app first via **Runner** scheme if needed)
5. Register bundle ID in Apple Developer: `com.golfmapapp.golfMapFlutter.watchkitapp`

## Usage

1. Start a round on the iPhone.
2. Open **Golf Map** on the watch.
3. If you see “Start a round on iPhone”, open the phone app once so it can push state.
4. Score on either device; changes sync within a few seconds.

## Requirements

- Paired Apple Watch (watchOS 10+)
- Location permission on the watch for yardage
