# Gravity Rocketeer

A single-level physics-puzzle proof-of-concept built in **Godot 4.7.x** (GDScript),
targeting the **iOS Simulator**. Drag to aim a fixed-speed rocket, release to
launch, and use a "wrong" planet's gravity to bend onto a path to the target. The
rocket lifts off from a thin strip of ground along the bottom of the full-screen
play area.

Playable with mouse-drag (which the iOS Simulator treats as touch).

---

## What's implemented

- **Drag-to-aim, fixed-speed launch** — the aim direction points from the ship
  toward your finger; drag distance only sets direction, not speed. Release
  launches at the constant `launch_speed`.
- **Live trajectory preview** that simulates forward with the real physics and
  **fades out** where it enters the wrong mass's sphere of influence — so you see
  the approach but not the result past it.
- **Real gravity** `F = G·m/r²` per body, summed each physics frame. Bodies pull
  only the ship, never each other. Preview and real flight share one integrator
  (`_sim_step`) so they always match.
- **Win / fail states**: WIN (within `landing_distance` of the target), EXPLODE
  (touch the wrong mass's physical radius), DRIFT (cross the world boundary).
- **Auto-restart on failure** after ~1s with no button; **Restart button only on
  WIN** (which also clears trails).
- **Flight trails** — the last 3 launches stay on screen, oldest most faded.
- **Live debug tuning overlay** (tap the **gear** button, top-right): sliders for
  G, launch speed, landing distance, world-boundary scale, and each body's mass /
  radii / position, plus **Reset to Defaults** and **Copy Values (print)**.

Current defaults: gravity `G = 2.0`, fixed `launch_speed = 225`, and the two
bodies enlarged (wrong-mass radius 80, target radius 68). The rocket now launches
from the very bottom, so it's a long flight up past the wrong mass — retune G,
the masses, speed, and positions from the debug overlay to make the assist as
necessary (or as forgiving) as you want.

## Project structure

| File | Role |
|------|------|
| `main.tscn` / `main.gd` | Scene tree + orchestrator (input, state machine, physics loop, trails, win/fail) |
| `gravity_body.gd` | A massive body (`mass`, `physical_radius`, `influence_radius`, `acceleration_at()`). Used by both `WrongMass` and `TargetPlanet`. |
| `earth.gd` | Launch-pad dome |
| `ship.gd` | Rocket triangle |
| `debug_overlay.gd` | Live tuning panel (CanvasLayer) |
| `test_sim.gd` | Dev-only headless check of the tuning (run: `godot --headless -s res://test_sim.gd`) |
| `gen_icons.gd` | Dev-only: regenerates `ios_icons/*.png` from `icon.svg` |
| `export_presets.cfg` | iOS export preset (simulator-oriented) |

All key tunables are `@export` on the relevant nodes, so editor-time and the
runtime overlay stay in sync.

---

## Running it

### 1. Open in Godot
Open `project.godot` with Godot **4.7.x**. Press **F5** to play on desktop
(mouse-drag = touch). Everything except the iOS packaging works here.

> On this Mac, Godot's **mobile** renderer (Vulkan/MoltenVK) can fail to present a
> desktop window. If the editor viewport is black when running on desktop, launch
> with the GL renderer: `godot --path . --rendering-method gl_compatibility`.
> This only affects desktop preview — the iOS build uses the mobile renderer.

### 2. Export for the iOS Simulator

Export templates must be installed for Godot 4.7.x (Editor → *Manage Export
Templates* → Download, or drop the `.tpz` into
`~/Library/Application Support/Godot/export_templates/4.7.1.stable/`).

The repo already contains a working `export_presets.cfg`. Generate the Xcode
project (no build/sign — `export_project_only=true` is set):

```bash
cd gravity-rocketeer
mkdir -p build/ios
godot --headless --path . --export-debug "iOS" "build/ios/GravityRocketeer.xcodeproj"
```

This writes the Xcode project + `.pck` + xcframeworks into `build/ios/`.

### 3. Build & run on the Simulator

Godot 4.7.1's iOS template ships an **x86_64-only** simulator engine library, so
the app must be built for **x86_64** (it runs on Apple-Silicon Simulators via
Rosetta). No code signing is needed for the Simulator.

```bash
SCR=build/ios/DerivedData
xcodebuild -project build/ios/GravityRocketeer.xcodeproj \
  -scheme GravityRocketeer -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$SCR" \
  ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO VALID_ARCHS=x86_64 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP="$SCR/Build/Products/Debug-iphonesimulator/GravityRocketeer.app"
xcrun simctl boot "iPhone 16" 2>/dev/null; open -a Simulator
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.strellus.gravityrocketeer
```

Or open `build/ios/GravityRocketeer.xcodeproj` in **Xcode**, pick an iPhone
Simulator, and press **Run** (▶). If Xcode links for arm64 and fails with an
undefined `_main`, set the target's **Architectures** to `x86_64` for the
simulator (see note above), or add `arm64` to *Excluded Architectures* for
`Any iOS Simulator SDK`.

### 4. Use the debug tuning overlay
Tap the **gear** button (top-right). Drag the sliders to retune G, masses, radii,
positions, launch speed, win threshold, and boundary — the running sim updates
live. **Reset to Defaults** restores the tuned starting values. **Copy Values
(print)** prints the current config as assignments to the Xcode/Godot console, so
a good configuration can be pasted back into the source as new defaults.

---

## Notes / known quirks (Godot 4.7 iOS export)

These non-obvious things are already handled in the repo:

- **`rendering/textures/vram_compression/import_etc2_astc=true`** must be set in
  `project.godot`, or mobile export fails with a *blank* configuration error.
- **`display/window/handheld/orientation=1`** must be the **integer** `1` (portrait).
  The exporter does `int(setting)`; the string `"portrait"` casts to `0`
  (landscape).
- **Team ID** is a placeholder (`0000000000`). The Simulator ignores signing; set
  your real Apple Team ID + a bundle identifier for on-device builds.
- **Device family** is universal (`targeted_device_family=2`).
- The min iOS version is **14.0** (Metal requires iOS 14+).
