# AGENTS.md

## Cursor Cloud specific instructions

### Platform requirement (important)

`SiteSinc` is a **native iOS/iPadOS app** built with **Xcode** (`SiteSinc.xcodeproj`). It
requires **macOS + Xcode 16 + the iOS 18 SDK/Simulator** to build, test, lint, or run.

- Target: `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `SUPPORTED_PLATFORMS = iphonesimulator iphoneos`.
- Uses Apple-only frameworks throughout: `SwiftUI`, `UIKit`, `CoreData`, `SwiftData`,
  `PhotosUI`, `PDFKit`, `WebKit`, `UserNotifications`, `CoreLocation`, `AVFoundation`,
  `LocalAuthentication`.
- Code signing is automatic (`Apple Development`, `DEVELOPMENT_TEAM = SX6FRQ2PP9`).

**Cursor Cloud Agent VMs run Linux (Ubuntu x86_64), so this project cannot be built,
tested, or run in the cloud environment.** `xcodebuild`/`xcrun`/`swift` are not available,
and the open-source Swift Linux toolchain does not ship the Apple UI/data frameworks this
app depends on. Do not attempt to create a Linux build/run setup for this repo — it is a
fundamental OS incompatibility, not a missing dependency.

### How to build / test / run (on macOS only)

Use the shared scheme `SiteSinc` (`SiteSinc.xcodeproj/xcshareddata/xcschemes/SiteSinc.xcscheme`):

- Build: `xcodebuild -project SiteSinc.xcodeproj -scheme SiteSinc -sdk iphonesimulator build`
- Test: `xcodebuild -project SiteSinc.xcodeproj -scheme SiteSinc -destination 'platform=iOS Simulator,name=iPhone 16' test`
  (test targets: `SiteSincTests`, `SiteSincUITests`).
- Run: open `SiteSinc.xcodeproj` in Xcode and run on an iOS Simulator or device.

### Notes

- There is no dependency manager (no Swift Package Manager `Package.swift`, no CocoaPods,
  no Carthage), so there is nothing to install before building in Xcode.
- The app talks to a remote backend over HTTPS (see `SiteSinc/APIClient.swift` and
  `NOTIFICATION_SETUP.md`); the backend is not part of this repository.
