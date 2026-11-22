# Swept

A calm, honest disk cleaner for macOS. Swept shows you what's taking up space in caches,
logs, leftovers from deleted apps, Xcode, the Trash and more, explains each item, and only
cleans what you choose.

## Download

**[Download the latest version](https://github.com/rebekkaorth/Swept/releases/latest)**

1. Open the `.dmg` and drag **Swept** into **Applications**.
2. Open Swept from Applications.
3. When asked, give Swept **Full Disk Access** in System Settings ▸ Privacy & Security.
   macOS needs this before any app can see other apps' caches.

Swept is signed with a Developer ID and notarized by Apple, so it opens without warnings.

**Requirements:** macOS 26 (Tahoe) or later.

## What Swept looks at

Xcode & Simulators · App Caches · Leftovers from deleted apps · Developer Tool Caches ·
Application Support · Logs · Saved App State · Trash · iOS Backups · Mail Attachments ·
Time Machine Snapshots · Downloads

It can also live in the menu bar, check your disk now and then, and remind you (at most once
a day) when there's more to clean than a limit you set.

## What Swept never does

- **No network.** Swept makes no network connections, has no analytics and no third-party code.
- **Trash first.** Cleaned items go to the Trash, so you can put them back. Only emptying the
  Trash and deleting Time Machine snapshots are permanent, and Swept asks before doing either.
- **Allowlist only.** Swept only touches folders on a fixed allowlist
  ([`ScanSources.swift`](Swept/Engine/ScanSources.swift)). Places like Mail, Messages, Photos,
  Keychains and iCloud Drive can be shown, but never deleted.
- **Nothing pre-checked that you might miss.** "Select all" only picks items that are safe to remove.

## Why Full Disk Access?

macOS hides other apps' data from every app unless you grant Full Disk Access. Swept uses it
only to read sizes and to move the items you choose to the Trash. You can revoke it any time
in System Settings ▸ Privacy & Security ▸ Full Disk Access.

## Uninstall

Quit Swept (menu bar icon ▸ Quit), then drag it from Applications to the Trash. Its settings
live in `~/Library/Preferences/com.rebekkaorth.Swept.plist`; you can delete that too.

## Build from source

1. Install Xcode 26 or later.
2. Clone the repo and open `Swept.xcodeproj`.
3. Target **Swept** ▸ Signing & Capabilities: set **Team** to your own, or choose
   **Sign to Run Locally**.
4. Run (⌘R). Run the tests with ⌘U.

Release builds (signing, notarization, DMG) are described in [BUILD.md](BUILD.md).

## Reporting problems

Bugs and ideas: [open an issue](https://github.com/rebekkaorth/Swept/issues).
If Swept deleted, or offered to delete, something it shouldn't, please report it privately:
see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © 2026 rebekkaorth
