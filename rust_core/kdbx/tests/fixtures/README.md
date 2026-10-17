These synthetic KeePass database fixtures are copied from the `keepass-rs`
project's MIT-licensed test resources:

- `kdbx4_argon2_aes.bin` — KDBX 4 with Argon2 and AES
- `kdbx4_argon2id_chacha20.bin` — KDBX 4 with Argon2id and ChaCha20
- `kdbx4_aes_kdf_aes_cipher.bin` — KDBX 4.1 with AES-KDF and AES
- `kdbx3_aes_kdf_aes_cipher.bin` — KDBX 3.1 with AES-KDF and AES

Source: https://github.com/sseemayer/keepass-rs/tree/master/tests/resources

The test password for both files is `demopass`. These files are test data only
and must never be used to store real credentials.
