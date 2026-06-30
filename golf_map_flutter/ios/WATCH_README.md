# Apple Watch Companion

The **South Texas Golf Tracker** watch app syncs with the iPhone app during an active round.

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

You need the **watchOS SDK** installed in Xcode (Settings → Components).

### Open the right Xcode project

**Use `ios/Runner.xcworkspace` — not `Runner.xcodeproj`.**

Opening the `.xcodeproj` causes `Module 'apple_maps_flutter' not found` because CocoaPods plugins are not linked.

```bash
./tool/open_xcode.sh
```

Then in Xcode:

1. **Scheme:** `Runner` (not `GolfMapWatch`)
2. **Destination:** your **iPhone** `KP` (not Kyle's Apple Watch)
3. **Product → Clean Build Folder** (⇧⌘K) if you hit stale errors
4. Press **Run** (⌘R)

The watch app is embedded in the iPhone build and syncs to your paired watch after install.

### Recommended: install iPhone + watch from terminal

`flutter run` updates the iPhone app but **does not reliably push the watch app** to your paired Apple Watch. Use the install script instead (it bumps the build number each run so watchOS will accept the update):

```bash
chmod +x tool/install_ios_with_watch.sh
./tool/install_ios_with_watch.sh KP          # debug
./tool/install_ios_with_watch.sh KP --release
./tool/install_ios_with_watch.sh KP --clean  # if you suspect a stale build
```

The Xcode **Runner** target runs a **Verify Watch Embed** check after every build — the build fails if `Watch/GolfMapWatch.app` is missing from `Runner.app`.

Or in Xcode: open `ios/Runner.xcworkspace`, select the **Runner** scheme and your **iPhone** (not the watch), then press **Run (⌘R)**.

After install, open the **Watch** app on iPhone → **Installed on Apple Watch** and confirm **South Texas Golf Tracker** is listed.

### If you still see an old watch UI

1. On iPhone: **Watch** app → remove any old golf / GolfMap watch apps.
2. On Apple Watch: long-press the old app icon → **Delete App**.
3. Run `./tool/install_ios_with_watch.sh KP` again (not `flutter run`).
4. Keep the watch unlocked and on your wrist during install.

### Do not use the GolfMapWatch scheme for day-to-day updates

Building with the **GolfMapWatch** scheme installs a **standalone** watch app that is separate from the iPhone companion bundle. That install will not update when you deploy from **Runner**, and vice versa. Always deploy with **Runner** → your **iPhone** as the destination.

### Hide the iPhone Live Activity card on Apple Watch

When you start a round, iOS **automatically mirrors** the iPhone Live Activity (lock screen / Dynamic Island scoring card) to your Apple Watch Smart Stack. Apple does not give apps an API to turn off that mirroring while keeping the iPhone Live Activity.

Use the **South Texas Golf Tracker** watch app for scoring on your wrist, and turn off the mirrored card on the watch:

1. On **Apple Watch**, open **Settings**
2. Tap **Smart Stack** → **Live Activities**
3. Turn off **Auto-Launch Live Activities** (stops it taking over the watch face)
4. Optionally turn off **Allow Live Activities** entirely, or adjust per-app options if **South Texas Golf Tracker** is listed

The iPhone lock screen Live Activity is unchanged — only the duplicate card on the watch is affected.

## Usage

1. Start a round on the iPhone.
2. Open **South Texas Golf Tracker** on the watch.
3. If you see “Waiting for round”, start a round on the phone so it can push state.
4. Score on either device; changes sync within a few seconds.

## Requirements

- Paired Apple Watch (watchOS 10+)
- Location permission on the watch for yardage
