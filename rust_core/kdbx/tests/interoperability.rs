use kdbx::{open, DatabaseKey, DatabaseVersion};

const FIXTURE_PASSWORD: &str = "demopass";

#[test]
fn opens_reference_kdbx4_argon2_aes_database() {
    let database = open(
        include_bytes!("fixtures/kdbx4_argon2_aes.bin"),
        DatabaseKey::new().with_password(FIXTURE_PASSWORD),
    )
    .unwrap();

    assert!(matches!(database.config.version, DatabaseVersion::KDB4(_)));
    assert_eq!(database.root().name, "Root");
    assert_eq!(database.root().entries().count(), 2);
}

#[test]
fn opens_reference_kdbx4_argon2id_chacha20_database() {
    let database = open(
        include_bytes!("fixtures/kdbx4_argon2id_chacha20.bin"),
        DatabaseKey::new().with_password(FIXTURE_PASSWORD),
    )
    .unwrap();

    assert!(matches!(database.config.version, DatabaseVersion::KDB4(_)));
    assert_eq!(database.root().name, "Root");
    assert_eq!(database.root().entries().count(), 1);
}

#[test]
fn opens_reference_kdbx4_aes_kdf_database() {
    let database = open(
        include_bytes!("fixtures/kdbx4_aes_kdf_aes_cipher.bin"),
        DatabaseKey::new().with_password(FIXTURE_PASSWORD),
    )
    .unwrap();

    assert_eq!(database.config.version, DatabaseVersion::KDB4(1));
    assert_eq!(database.root().name, "Root");
    assert_eq!(database.root().entries().count(), 1);
}

#[test]
fn opens_reference_kdbx3_database_with_legacy_header_fields() {
    let database = open(
        include_bytes!("fixtures/kdbx3_aes_kdf_aes_cipher.bin"),
        DatabaseKey::new().with_password(FIXTURE_PASSWORD),
    )
    .unwrap();

    assert_eq!(database.config.version, DatabaseVersion::KDB3(1));
    assert_eq!(database.root().name, "sample");
    assert_eq!(database.root().entries().count(), 2);
}

#[test]
fn reencodes_and_reopens_a_reference_kdbx4_1_database() {
    let database = open(
        include_bytes!("fixtures/kdbx4_aes_kdf_aes_cipher.bin"),
        DatabaseKey::new().with_password(FIXTURE_PASSWORD),
    )
    .unwrap();
    let mut encoded = Vec::new();

    kdbx::save_kdbx4(
        &database,
        DatabaseKey::new().with_password(FIXTURE_PASSWORD),
        &mut encoded,
    )
    .unwrap();

    let reopened = open(&encoded, DatabaseKey::new().with_password(FIXTURE_PASSWORD)).unwrap();
    assert_eq!(reopened, database);
}
