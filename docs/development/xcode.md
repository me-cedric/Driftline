# Generated Xcode Project

SwiftPM remains Driftline's default build/test path. Xcode exists for native app/widget packaging that SwiftPM cannot produce alone.

## Generator

Driftline uses XcodeGen because the current project is a simple macOS app, widget extension, shared frameworks, and tests. No Swift manifest generator is needed yet.

Install:

```bash
brew install xcodegen
```

Generate:

```bash
./scripts/generate-xcode-project.sh
open Driftline.xcodeproj
```

Generated path: `Driftline.xcodeproj`. It is ignored by git and reproduced from `project.yml`.

## Targets

- `Driftline`: macOS app, bundle id `app.driftline.Driftline`.
- `DriftlineWidgetExtension`: WidgetKit extension target, bundle id `app.driftline.Driftline.Widget`, product `DriftlineWidget.appex`.
- `DriftlineCore`, `DriftlineMCP`, `DriftlineWidget`: shared framework targets.
- `DriftlineCoreTests`, `DriftlineMCPTests`: Xcode test targets where feasible.

## Signing

Defaults live in `packaging/config/DriftlineXcode.xcconfig`.

Local values belong in ignored `packaging/config/DriftlineSigning.xcconfig`:

```bash
cp packaging/config/DriftlineSigning.xcconfig.template packaging/config/DriftlineSigning.xcconfig
```

Set `DEVELOPMENT_TEAM`, signing style/profile values, and `DRIFTLINE_APP_GROUP_IDENTIFIER`. Do not commit personal team ids or real App Group ids.

Create the App Group in Apple Developer:

1. Open Certificates, Identifiers & Profiles.
2. Create an App Group for Driftline, for example `group.<owned-domain>.Driftline`.
3. Enable that group on both app identifiers: `app.driftline.Driftline` and `app.driftline.Driftline.Widget`.
4. Refresh local provisioning profiles if Xcode does not do it automatically.

Minimal local config:

```xcconfig
DEVELOPMENT_TEAM = <your-team-id>
DRIFTLINE_APP_GROUP_IDENTIFIER = group.<owned-domain>.Driftline
CODE_SIGN_STYLE = Automatic
```

Unsigned compile validation:

```bash
./scripts/validate-xcode-project.sh
xcodebuild -project Driftline.xcodeproj -scheme Driftline -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Driftline.xcodeproj -scheme DriftlineWidgetExtension -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Driftline.xcodeproj -scheme DriftlineCore -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Driftline.xcodeproj -scheme DriftlineWidget -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild test -project Driftline.xcodeproj -scheme DriftlineCoreTests -configuration Debug CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Driftline.xcodeproj -scheme DriftlineMCPTests -configuration Debug CODE_SIGNING_ALLOWED=NO
```

Signed validation:

```bash
./scripts/build-signed-xcode-app.sh
./scripts/validate-widget-packaging.sh
```

Output app path: `dist/xcode/Driftline.app`.

## Widget Test

1. Generate project.
2. Configure signing and App Group.
3. Build `Driftline`: `./scripts/build-signed-xcode-app.sh`.
4. Validate packaging: `./scripts/validate-widget-packaging.sh`.
5. Install/launch signed app:

```bash
open dist/xcode/Driftline.app
```

6. Add Driftline in macOS widget gallery.
7. Verify sanitized transfer state and `driftline://` actions.
8. Change profiles, favorites, recents, or transfer state in Driftline and confirm widget snapshot updates.

Unsupported: release packaging still uses SwiftPM bundle scripts, so shipping widget packaging is not complete until release scripts build/sign/notarize the Xcode app bundle with embedded `.appex`.
