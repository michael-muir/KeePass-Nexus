# KeePass Nexus for Windows

This is the first desktop client for KeePass Nexus. It uses Flutter for the
interface and calls the existing Rust KDBX engine through
`flutter_rust_bridge`.

## Prerequisites

- Flutter stable with Windows desktop enabled
- Rust 1.89 or newer
- Visual Studio with the **Desktop development with C++** workload

## Setup

From this directory, install the Dart dependencies and regenerate the Rust
bridge bindings:

```powershell
flutter pub get
cargo install flutter_rust_bridge_codegen --version 2.13.0
.\scripts\generate_bridge.ps1
```

Run the Windows application with:

```powershell
flutter run -d windows
```

The unlock screen accepts a KDBX file, master password, and optional key file.
The open vault supports nested group browsing, entry create/read/update/delete,
search, encrypted save, theme settings, and inactivity auto-lock. Password
values are returned to the UI only when opening the selected entry editor or
details panel and are masked by default.

The entry editor's password field includes a generator with character and
passphrase modes, entropy feedback, show/hide, refresh, copy, and clipboard
clear actions. Passwords are generated with Dart's secure random source. The
entry editor also supports KeePass built-in icons, uploaded custom icons, and
favicon downloads from the URL's standard favicon paths. Icons are embedded in
the KDBX database and shown in the entry list and details pane. The
entry editor stores whitespace-separated tags and native KDBX expiration
metadata, with date/time selection and relative presets. Expiry timestamps use
UTC at the precision supported by KDBX. Notes remain part of the entry form.
Entries also support favorites, cloning, custom fields, file attachments, and
viewing/restoring entry history. Attachments can be added and exported; removing
an existing attachment is disabled because the current KDBX library cannot
preserve attachment references in historical revisions when it is removed.
Deleted entries and groups are moved to the database recycle bin, where they
can be restored or permanently deleted. Groups can be renamed and moved.
Favorite and tag filters are available in the vault navigation, and recently
viewed entries are tracked for the current open session. The unlock screen
retains up to ten recent database paths on the device.
The client currently opens one database at a time, and group ordering remains
alphabetical rather than user-configurable.
The client verifies generated KDBX files by reopening them and comparing the
decoded database model before committing them to disk. Saves create and verify
a recovery copy at `<database>.nexus-backup`; changes made to the file outside
the app are detected and not overwritten. Saving a KDBX 3 database requires
explicit confirmation to convert it to KDBX 4.1; saving a KDBX 4.0 database
requires explicit confirmation to upgrade it to 4.1. Both upgrades occur only
after the recovery copy has been verified. Closing the desktop window with
unsaved changes offers save, discard, and cancel.

The Rust interoperability suite includes KeePassXC's pinned KDBX 3.0 and
KDBX 4.0 test databases, as well as KDBX 3.1 and KDBX 4.1 fixtures covering
AES-KDF, Argon2, Argon2id, AES, and ChaCha20. Automated tests verify parsing
and round-tripping the supported model; validating generated files in the
KeePassXC application remains a separate release check.

The Windows runner requests exclusion from supported screen-capture APIs using
[`SetWindowDisplayAffinity`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity);
Windows documents this as best effort, and it does not prevent external cameras
or guarantee protection from every capture path. Other platforms do not yet
have screen-capture protection.
