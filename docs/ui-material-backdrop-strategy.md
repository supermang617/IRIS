# UI Material And Backdrop Strategy

Status: future UI polish plan, not current implementation.

## Current UI architecture

Project Iris is currently using the native Rust HUD path:

- iris-ui
- egui
- eframe
- winit through eframe

This remains the active v0.1 HUD direction.

Do not switch to Tauri unless we explicitly decide to replace the native Rust HUD with a webview-based UI.

## Why not Tauri now

Tauri is a valid desktop UI architecture, but switching now would add:

- webview runtime assumptions
- frontend asset pipeline
- HTML/CSS state layer
- Tauri configuration
- extra packaging concerns
- a second UI architecture while the current HUD is still being built

That is unnecessary for the first working Iris HUD.

## Current priority

The first HUD must prove:

- Iris-owned typed prompt input
- response display
- visible voice state
- safety absence language
- no system control
- no input simulation
- no runtime network
- no plugins
- no wake word runtime yet
- no screen capture yet
- no OCR yet
- no memory database yet

Visual polish comes after the HUD works.

## Windows 11 material target

Preferred future Windows material:

Mica

Reason:

- native Windows 11 look
- lower overhead than continuous blur
- better fit for thermal-safe design
- subtle desktop integration
- appropriate for a calm assistant HUD

Secondary option:

Acrylic

Use only if Mica does not fit the Iris visual direction.

Acrylic should be treated as more visually aggressive and potentially more expensive than Mica.

## Future platform material map

Windows:

- Mica first
- Acrylic optional

macOS:

- native vibrancy / material backdrop

Android:

- Material You dynamic color palette

iOS:

- native system materials inside app surfaces

## Design rule

Use native compositor materials where available.

Do not simulate heavy blur in the app render loop.

Do not add high-frequency transparency or blur effects that increase CPU, GPU, battery, or thermal load.

Always provide a solid dark fallback theme.

## Implementation timing

Do not implement native material/backdrop effects until after:

1. minimal HUD opens reliably
2. typed prompt reaches Iris runtime
3. checked response displays in HUD
4. Kokoro speech can be triggered from the HUD path
5. visible voice state is represented in the HUD
6. Panic Stop behavior is visible
7. diagnostics remain clean

## Tauri note

If Iris ever switches to Tauri in a later architecture decision, then the transparent-window approach may be reconsidered:

- transparent native window
- no OS decorations
- custom drag region
- transparent frontend root
- native Mica/Acrylic/Vibrancy through a platform bridge

This is not the current path.

## Current decision

Lock the material/backdrop idea as future UI polish.

Do not add Tauri.

Do not add window-vibrancy.

Do not change the current egui/eframe HUD architecture.
