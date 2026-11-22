# Building & Releasing Swept

Swept ships as a **non-sandboxed, Hardened-Runtime, Developer ID–signed, notarized** macOS
app (macOS 26 Tahoe+). **Not** the Mac App Store. Swept uses **no network** and no third-party
dependencies.

---

## 1. Prerequisites

- Xcode 26+ on macOS 26+ (Tahoe).
- Apple Developer Program membership (Team ID `YOUR_TEAM_ID`).
- A **Developer ID Application** certificate in your login keychain
  (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ *Developer ID Application*).
- For notarization: your Apple ID + an **app-specific password**
  (<https://account.apple.com> ▸ Sign-In & Security ▸ App-Specific Passwords),
  or an App Store Connect API key.

---

## 2. One-time Xcode project settings

These live in `project.pbxproj` and must be set in Xcode's UI (Target **Swept**):

**Signing & Capabilities**
- Team: **YOUR_TEAM_ID**.
- **Hardened Runtime: ON** (`ENABLE_HARDENED_RUNTIME = YES`, set).
- **App Sandbox: OFF** (do *not* add the App Sandbox capability).
- Code Signing Entitlements → `Swept/Swept.entitlements` (already in the repo; sets
  `com.apple.security.app-sandbox = false`, nothing else).
- Release configuration: sign with **Developer ID Application** (Automatic signing is fine;
  Xcode picks the Developer ID cert for the `developer-id` export).

**Build Settings**
- **macOS Deployment Target = 26.0** (set) — drives `LSMinimumSystemVersion`.
- Product Bundle Identifier → **`com.rebekkaorth.Swept`** (set).
- Under **Info.plist Values** (Generate Info.plist File = YES):
  - `INFOPLIST_KEY_CFBundleDisplayName` = `Swept`
  - `INFOPLIST_KEY_NSHumanReadableCopyright` = `© 2026 rebekkaorth. Released under the MIT License.`
  - Version = `MARKETING_VERSION` (1.0) / build = `CURRENT_PROJECT_VERSION` (1).
- No usage-description strings are needed — Swept uses no camera/mic/location/etc. Full Disk
  Access is requested via System Settings, which needs no Info.plist key.

---

## 3. Verify the privacy claim (run before every release)

```sh
# Must print NO matches:
grep -rniE "URLSession|NSURLConnection|NWConnection|import Network|CFSocket|getaddrinfo|CFStream|URLRequest|dataTask|WebSocket|Firebase|Sentry|Amplitude|Mixpanel|Crashlytics|\bSegment\b|Bugsnag|Alamofire|analytics|telemetry" --include="*.swift" Swept/

# Must print NO matches (no hardcoded web endpoints):
grep -rniE "http" --include="*.swift" Swept/
```
There are also no Swift Package / third-party dependencies (no `Package.resolved`).

---

## 4. Archive → Export → Notarize → Staple → Verify

Run from the repo root. `ExportOptions.plist` is in the repo.

```sh
# 0. Clean output dir
rm -rf build && mkdir build

# 1. Archive (Release)
xcodebuild \
  -project Swept.xcodeproj \
  -scheme Swept \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/Swept.xcarchive \
  archive

# 2. Export a Developer ID–signed app (uses ExportOptions.plist: method = developer-id)
xcodebuild -exportArchive \
  -archivePath build/Swept.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
# → build/export/Swept.app

# 3. (one-time) Store notarization credentials in the keychain under a profile name
xcrun notarytool store-credentials "AC_PROFILE" \
  --apple-id "YOUR_APPLE_ID@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"

# 4. Zip the .app (preserve bundle) and submit for notarization
ditto -c -k --keepParent "build/export/Swept.app" "build/Swept.zip"
xcrun notarytool submit "build/Swept.zip" --keychain-profile "AC_PROFILE" --wait
#   → wait for "status: Accepted". If "Invalid", inspect the log:
#   xcrun notarytool log <submission-id> --keychain-profile "AC_PROFILE"

# 5. Staple the ticket onto the .app
xcrun stapler staple "build/export/Swept.app"

# 6. Verify (both must pass)
spctl -a -vvv -t install "build/export/Swept.app"
#   → expect: source=Notarized Developer ID  /  accepted
codesign --verify --deep --strict --verbose=2 "build/export/Swept.app"
#   → expect: "valid on disk" and "satisfies its Designated Requirement"
```

---

## 5. Package for distribution

**Zip** (simplest):
```sh
ditto -c -k --keepParent "build/export/Swept.app" "build/Swept-1.0.zip"
```

**DMG** (nicer):
```sh
hdiutil create -volname "Swept" -srcfolder "build/export/Swept.app" \
  -ov -format UDZO "build/Swept-1.0.dmg"
xcrun stapler staple "build/Swept-1.0.dmg"   # staple the DMG too
```
(Or use `create-dmg` for a Finder-styled window.)

---

## 6. Future: Mac App Store (NOT now)

If Swept ever targets MAS, these change (leave as-is until then):
- **Strip the icon's alpha channel** — MAS rejects icons with alpha. Flatten
  `AppIcon-1024.png` onto an opaque background before importing.
- **Enable App Sandbox** (`com.apple.security.app-sandbox = true`) and add a security-scoped
  bookmark / `NSOpenPanel` folder-grant flow, since a sandboxed app can't freely read
  `~/Library`. This is a significant re-architecture of the scan/delete engine.
- Switch signing to **Apple Distribution** + a MAS provisioning profile, and export with
  `method = app-store`.
