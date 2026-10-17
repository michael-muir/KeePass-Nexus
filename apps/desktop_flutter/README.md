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
Windows runner requests exclusion from supported screen-capture APIs using
[`SetWindowDisplayAffinity`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity);
Windows documents this as best effort, and it does not prevent external cameras
or guarantee protection from every capture path. Other platforms do not yet
have screen-capture protection.
