# KeePass Nexus Handoff

## Project status

The project has a Rust KDBX engine and a Windows-first Flutter desktop client.
The Flutter app connects to Rust using `flutter_rust_bridge` and supports
unlocking or creating a vault, browsing groups and entries, editing entries,
searching, encrypted saving, settings, and inactivity auto-lock.

## Completed work

- Added checked group and entry CRUD operations to `rust_core/kdbx`, including
  missing-ID errors, recursive group deletion, entry history tracking, and
  protected-field handling.
- Added the Flutter app under `apps/desktop_flutter` and a Rust bridge crate
  that wraps the existing KDBX API.
- Implemented password and optional key-file unlock, vault creation, database
  snapshots, entry read/search/create/update/delete, and encrypted save.
- Added checked entry move-to-group support in the Rust KDBX facade and exposed
  it through the Flutter bridge and vault controller.
- Added a KeePassXC-inspired password generator to the entry editor, with
  character and passphrase tabs, configurable character groups, exclusions,
  secure random generation, entropy/quality feedback, refresh, show/hide, copy,
  and clipboard clearing.
- Added best-effort Windows screen-capture exclusion using
  `SetWindowDisplayAffinity` with `WDA_EXCLUDEFROMCAPTURE`.
- Added the Windows Flutter runner, Cargokit integration, generated bridge
  bindings, and a Windows-specific bridge generation script.
- Updated `docs/specifications/technical-specifications.md` with CRUD and
  Flutter architecture details, and added Windows setup, password generation,
  and screen-capture protection notes in the app README.
- Restored the intended Flutter app bootstrap after bridge integration had
  replaced it with a starter sample.

## Validation

The following checks passed:

- `flutter analyze`
- `flutter test`
- `cargo test --quiet` in `rust_core/kdbx`
- `cargo fmt`
- `cargo clippy --all-targets -- -D warnings`
- `cargo test`
- `flutter build windows`

## Known limitations and next steps

- KDBX 4 serialization limitations remain as described in
  `docs/specifications/technical-specifications.md`; validate interoperability
  with KeePassXC before relying on the writer for production databases.
- The current UI work is Windows-first. Android, iOS, macOS, and Linux
  packaging and platform-specific security integrations are not yet validated.
- Windows screen-capture exclusion is best effort and does not prevent external
  cameras or guarantee protection from every capture method. Other platforms
  do not yet have screen-capture protection.
- Continue with KeePassXC interoperability testing and address any compatibility
  issues before broadening platform support.

## Development

See `apps/desktop_flutter/README.md` for prerequisites and Windows setup. To
regenerate the Rust bridge, run `.\scripts\generate_bridge.ps1` from
`apps/desktop_flutter`.
