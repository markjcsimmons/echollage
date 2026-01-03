# Ogenblick (iOS)

Capture a sound, create a visual collage from photos with drawings and text, and share as a video with audio. First 3 exports are free; then subscribe.

## Prerequisites
- Xcode 15+
- iOS 16+
- CocoaPods (optional if adding ACRCloud SDK via Pod)
- Homebrew (for XcodeGen install)

## Setup
1) Install XcodeGen (if not already):
```bash
brew install xcodegen
```

2) Generate the Xcode project:
```bash
cd "$(dirname "$0")"
xcodegen generate
open Ogenblick.xcodeproj
```

3) Configure ACRCloud (for music recognition):
- Create `Ogenblick/Resources/Secrets.plist` by copying the sample:
```bash
cp Ogenblick/Resources/Secrets.sample.plist Ogenblick/Resources/Secrets.plist
```
- Update the values:
  - `host`: the full HTTPS endpoint for your project (e.g. `https://identify-us-west-2.acrcloud.com`)
  - `accessKey` and `accessSecret`: from the ACRCloud dashboard
- The app sends a short audio sample to ACRCloud’s REST API after recording and adds the detected `title • artist` to the collage automatically.
  - If the request returns “no result” the user can proceed without metadata.

4) Configure StoreKit (optional for MVP):
- In `PurchaseManager`, replace placeholder product IDs with your own.
- For local testing, add a StoreKit Configuration file in Xcode and set it as the run scheme’s StoreKit config.

## Targets
- App target: `Ogenblick`
- Minimum iOS: 16.0

## Features (MVP)
- Audio record/playback using `AVFoundation`
- Multi-photo collage with drag/scale/rotate
- Freehand drawing via PencilKit overlay
- Text labels
- Persist editable projects to disk (JSON)
- Export MP4 (static collage + recorded audio)
- Share via system share sheet
- 3 free exports; paywall scaffolding with StoreKit 2
- ACRCloud music recognition (requires credentials in `Secrets.plist`)

## Folder structure
- `Ogenblick/App` – App entry, composition
- `Ogenblick/UI` – Screens and UI components
- `Ogenblick/Features` – Recording, Editor, Export, Paywall, etc.
- `Ogenblick/Data` – Models and persistence
- `Ogenblick/Resources` – Info.plist, secrets, assets

## Notes
- Large photos are downscaled on import for memory safety.
- Export resolution defaults to longest edge 1920px.
- First 3 exports are counted via `UserDefaults`; replace with entitlement check when subscription is active.

## Roadmap
- ACRCloud full SDK integration
- Templates, filters, stickers
- Cloud sync (CloudKit)
- Subtle Ken Burns animation during export

## Privacy
Add and customize the usage descriptions in `Info.plist` before release.


