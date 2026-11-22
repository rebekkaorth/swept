# Releasing Swept

How the official download is made. Swept is distributed through GitHub Releases as a
**Developer ID–signed, notarized** DMG, so it opens on any Mac without warnings. It is not on
the Mac App Store.

To just build and run Swept on your own Mac, see "Build from source" in the [README](README.md).

---

## One-time setup

1. **Apple Developer Program** membership.
2. A **Developer ID Application** certificate in your keychain:
   Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ *Developer ID Application*.
3. **Your Team ID** in `Config/Local.xcconfig` (git-ignored): copy
   `Config/Local.xcconfig.example` and fill it in. Don't set the team in Xcode's Signing &
   Capabilities tab, because Xcode would write it into the committed project file.
4. **Notarization credentials** stored in your keychain under the name `AC_PROFILE`. Use an
   app-specific password from <https://account.apple.com> ▸ Sign-In & Security, never your
   Apple ID password:
   ```sh
   xcrun notarytool store-credentials "AC_PROFILE" \
     --apple-id "YOUR_APPLE_ID@example.com" \
     --team-id "YOUR_TEAM_ID" \
     --password "YOUR_APP_SPECIFIC_PASSWORD"
   ```

---

## Every release

Run the commands from the repo root.

### 1. Set the version

In Xcode ▸ target **Swept** ▸ General: raise **Version** (e.g. 1.1) and **Build** (e.g. 2).
Update the version badge and the "Version X.Y" line under the download button in `README.md`.

### 2. Check that Swept still makes no network connections

Both commands must print **nothing**:

```sh
grep -rniE "URLSession|NSURLConnection|NWConnection|import Network|CFSocket|getaddrinfo|CFStream|URLRequest|dataTask|WebSocket|Firebase|Sentry|Amplitude|Mixpanel|Crashlytics|\bSegment\b|Bugsnag|Alamofire|analytics|telemetry" --include="*.swift" Swept/
grep -rniE "http" --include="*.swift" Swept/
```

### 3. Run the tests

```sh
xcodebuild test -project Swept.xcodeproj -scheme Swept -destination 'platform=macOS'
```

### 4. Build and sign the app

```sh
rm -rf build && mkdir build

xcodebuild archive \
  -project Swept.xcodeproj -scheme Swept -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/Swept.xcarchive

xcodebuild -exportArchive \
  -archivePath build/Swept.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
# → build/export/Swept.app, signed with your Developer ID
```

### 5. Have Apple notarize the app, then attach the approval

```sh
ditto -c -k --keepParent build/export/Swept.app build/Swept.zip
xcrun notarytool submit build/Swept.zip --keychain-profile "AC_PROFILE" --wait
# Wait for "status: Accepted". If it says "Invalid", read why:
#   xcrun notarytool log <submission-id> --keychain-profile "AC_PROFILE"
xcrun stapler staple build/export/Swept.app
```

### 6. Make the DMG, notarize it too, attach the approval

```sh
hdiutil create -volname "Swept" -srcfolder build/export/Swept.app \
  -ov -format UDZO build/Swept.dmg
xcrun notarytool submit build/Swept.dmg --keychain-profile "AC_PROFILE" --wait
xcrun stapler staple build/Swept.dmg
```

Keep the file name `Swept.dmg` for every version, so links to the latest download keep working.

### 7. Verify

```sh
spctl -a -vvv -t install build/export/Swept.app   # expect: accepted, source=Notarized Developer ID
spctl -a -vvv -t open --context context:primary-signature build/Swept.dmg   # expect: accepted
codesign --verify --deep --strict --verbose=2 build/export/Swept.app       # expect: valid on disk
shasum -a 256 build/Swept.dmg                     # copy this into the release notes
```

### 8. Publish

GitHub ▸ Releases ▸ *Draft a new release* ▸ tag `vX.Y` ▸ attach `build/Swept.dmg` ▸ paste the
SHA-256 and a short list of changes ▸ Publish.

Then download the DMG **through a browser** on another Mac (or a new user account) and open it,
to check it opens without a warning, the way your users will get it.
