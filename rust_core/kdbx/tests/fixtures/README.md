These test-only KeePass database fixtures include the `keepass-rs` project's
MIT-licensed synthetic resources:

- `kdbx4_argon2_aes.bin` — KDBX 4 with Argon2 and AES
- `kdbx4_argon2id_chacha20.bin` — KDBX 4 with Argon2id and ChaCha20
- `kdbx4_aes_kdf_aes_cipher.bin` — KDBX 4.1 with AES-KDF and AES
- `kdbx3_aes_kdf_aes_cipher.bin` — KDBX 3.1 with AES-KDF and AES

It also includes two upstream KeePassXC format fixtures, pinned to commit
`aabfb3858b98671e1f6ad1ffce70a418ba539fbc`:

- `keepassxc_format300.kdbx` — KDBX 3.0; test password `a`
- `keepassxc_format400.kdbx` — KDBX 4.0; test password `t`; includes an
  attachment and custom attributes

Upstream fixture files:

- https://github.com/keepassxreboot/keepassxc/blob/aabfb3858b98671e1f6ad1ffce70a418ba539fbc/tests/data/Format300.kdbx
- https://github.com/keepassxreboot/keepassxc/blob/aabfb3858b98671e1f6ad1ffce70a418ba539fbc/tests/data/Format400.kdbx

The upstream tests documenting those passwords and expected contents are
`tests/TestKdbx3.cpp` and `tests/TestKdbx4.cpp` at the same commit. All fixture
databases are test data only and must never be used to store real credentials.
