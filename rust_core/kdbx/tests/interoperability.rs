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
fn opens_keepassxc_kdbx3_fixture_and_converts_without_model_loss() {
    let database = open(
        include_bytes!("fixtures/keepassxc_format300.kdbx"),
        DatabaseKey::new().with_password("a"),
    )
    .unwrap();
    assert_eq!(database.config.version, DatabaseVersion::KDB3(0));
    assert_eq!(database.root().name, "Format300");
    assert_eq!(
        database.meta.database_name.as_deref(),
        Some("Test Database Format 0x00030000")
    );

    let mut expected = database.clone();
    expected.config.version = DatabaseVersion::KDB4(1);
    let mut encoded = Vec::new();
    kdbx::save_as_kdbx4(
        &database,
        DatabaseKey::new().with_password("a"),
        &mut encoded,
    )
    .unwrap();

    let reopened = open(&encoded, DatabaseKey::new().with_password("a")).unwrap();
    assert_eq!(reopened, expected);
}

#[test]
fn opens_and_round_trips_keepassxc_kdbx4_fixture_with_attachments_and_attributes() {
    let database = open(
        include_bytes!("fixtures/keepassxc_format400.kdbx"),
        DatabaseKey::new().with_password("t"),
    )
    .unwrap();
    assert_eq!(database.config.version, DatabaseVersion::KDB4(0));
    assert_eq!(database.root().name, "Format400");
    assert_eq!(database.meta.database_name.as_deref(), Some("Format400"));
    assert_eq!(database.num_attachments(), 1);

    let root = database.root();
    let entry = root.entries().next().unwrap();
    assert_eq!(entry.get("Format400"), Some("Format400"));
    assert_eq!(entry.attachments().count(), 1);

    let mut expected = database.clone();
    expected.config.version = DatabaseVersion::KDB4(1);
    let mut encoded = Vec::new();
    kdbx::save_as_kdbx4(
        &database,
        DatabaseKey::new().with_password("t"),
        &mut encoded,
    )
    .unwrap();
    let reopened = open(&encoded, DatabaseKey::new().with_password("t")).unwrap();
    assert_eq!(reopened, expected);
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
