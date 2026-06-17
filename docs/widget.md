# Driftline Widget

Driftline has a WidgetKit support module at `Sources/DriftlineWidget` and a generated Xcode widget extension target.

The module provides a small/medium macOS status widget layout, a timeline provider, safe open actions, and sample preview data. The repository is still SwiftPM-first. The embedded `.appex` is built through the generated Xcode project, not faked by SwiftPM scripts.

## Purpose

The widget shows non-secret Driftline state:

- current state: `idle`, `transferring`, or `error`
- active transfer count
- queued transfer count
- failed transfer count
- up to two recent/favorite connection actions in the medium widget

Widget actions use the existing URL contract:

```text
driftline://open
driftline://connect?protocol=sftp&host=example.com&port=22&username=demo&path=%2F
```

Opening a connection action pre-fills Driftline Quick Connect. Driftline does not auto-connect from widget URLs.

## Supported Families

- Small: app name/icon, transfer state, counts, open Driftline link.
- Medium: status summary plus up to two sanitized recent/favorite connection links.

Large is intentionally not implemented yet because the current state model does not need the extra space.

## Shared State

The app writes a sanitized `DriftlineIntegrationState` snapshot through `JSONDriftlineIntegrationStateStore` whenever profiles, favorites, recents, visible session errors, or transfer counts change. The SwiftPM widget support module reads that same local non-secret snapshot by default. The snapshot contains only integration-safe fields:

- display name
- protocol
- host
- port
- username when already shown in app UI
- remote path
- last-used date
- favorite flag
- transfer counts/status

The widget provider reads through `DriftlineWidgetSnapshotProvider`. If the snapshot is missing or unreadable, it falls back to an idle empty state.

## Packaging Strategy

Current model: SwiftPM-first app bundle script plus generated Xcode project for WidgetKit packaging.

- `swift build` and `swift test` remain the default developer flow.
- `script/build_and_run.sh` still builds `dist/Driftline.app`.
- `project.yml` generates `Driftline.xcodeproj` through XcodeGen.
- `DriftlineWidgetExtension` builds the embedded `DriftlineWidget.appex`.
- `DRIFTLINE_APP_GROUP_IDENTIFIER` points app/widget code at the shared sanitized snapshot when signing is configured.

## App Group Setup

Required Apple identifiers:

- App bundle id: `app.driftline.Driftline`
- Widget bundle id: `app.driftline.Driftline.Widget`
- App Group id: chosen in Apple Developer and kept in local signing config, for example `group.<owned-domain>.Driftline`

In Apple Developer, create the App Group, then enable it for both the app identifier and widget identifier. Refresh local provisioning profiles if automatic signing does not pick up the new capability.

Local config:

```bash
cp packaging/config/DriftlineSigning.xcconfig.template packaging/config/DriftlineSigning.xcconfig
```

Set `DEVELOPMENT_TEAM` and `DRIFTLINE_APP_GROUP_IDENTIFIER` in the local xcconfig. Use signing style/profile values only if your Apple account needs them. Do not commit a personal team id or account-specific group id unless the project officially owns it.

```xcconfig
DEVELOPMENT_TEAM = <your-team-id>
DRIFTLINE_APP_GROUP_IDENTIFIER = group.<owned-domain>.Driftline
CODE_SIGN_STYLE = Automatic
```

The app and widget read the group id from `DRIFTLINE_APP_GROUP_IDENTIFIER` in `Info.plist` or the environment. If unset or unavailable, they fall back to the normal app-support snapshot for SwiftPM development.

## Generated Xcode Project

Install XcodeGen:

```bash
brew install xcodegen
```

Generate:

```bash
./scripts/generate-xcode-project.sh
```

Targets:

- `Driftline`: macOS app, bundle id `app.driftline.Driftline`.
- `DriftlineWidgetExtension`: WidgetKit app extension, bundle id `app.driftline.Driftline.Widget`, product `DriftlineWidget.appex`.
- `DriftlineCore`, `DriftlineMCP`, `DriftlineWidget`: shared framework targets.
- `DriftlineCoreTests`, `DriftlineMCPTests`: test targets where Xcode can host them.

Signing lives in `packaging/config/DriftlineXcode.xcconfig`, with optional local overrides in ignored `packaging/config/DriftlineSigning.xcconfig`.

Do not hardcode a local Team ID. Do not store secrets in entitlements, plists, docs, tests, fixtures, or logs.

## Manual Test

Build and test the compile-tested SwiftPM widget module:

```bash
swift build
swift test
./scripts/lint.sh
```

Build the regular SwiftPM app bundle:

```bash
./script/build_and_run.sh --verify
```

Build the app with an App Group plist key and signed app entitlement:

```bash
DRIFTLINE_APP_GROUP_IDENTIFIER="<app-group-id>" \
DRIFTLINE_SIGN_IDENTITY="Developer ID Application: Example Company, Inc. (<team-id>)" \
./script/build_and_run.sh --verify
```

Validate generated Xcode app/widget compile without signing:

```bash
./scripts/validate-xcode-project.sh
```

Validate signed Xcode app/widget build:

```bash
./scripts/generate-xcode-project.sh
./scripts/build-signed-xcode-app.sh
./scripts/validate-widget-packaging.sh
```

To inspect the local sanitized snapshot written by the SwiftPM app during development:

```bash
cat "$HOME/Library/Application Support/Driftline/integration-snapshot.json"
```

1. Build signed app: `./scripts/build-signed-xcode-app.sh`.
2. Install/launch it: `open dist/xcode/Driftline.app`.
3. Add Driftline from the macOS widget gallery.
4. Launch Driftline and create or use a connection.
5. Confirm the widget updates sanitized state after profiles, favorites, recents, or transfer status changes.
6. Test URL actions:

```bash
open 'driftline://open'
open 'driftline://connect?protocol=sftp&host=example.com&port=22&username=demo&path=%2F'
```

## Limitations

- SwiftPM builds the widget support module, not a signed embedded WidgetKit `.appex`.
- XcodeGen creates the Xcode project, but shipping still needs Apple App Group provisioning and nested code signing.
- `scripts/validate-widget-packaging.sh` fails until signed `dist/xcode/Driftline.app` contains a signed widget `.appex`.
- Widget data is local and non-secret only.
- The widget does not poll networks, start transfers, or read credential stores.
- Raycast remains separate and continues using the same URL contract.

## Security

Never put credentials or credential references in widget timelines, shared JSON, previews, URLs, logs, fixtures, or screenshots. All widget connection actions must remain drafts opened in Driftline, where credentials stay behind `CredentialStore`.
