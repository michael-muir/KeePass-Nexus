//! KeePass database access for KeePass-Nexus.
//!
//! The format implementation is provided by the `keepass` crate, which
//! implements KDB, KDBX 3, and KDBX 4 parsing, key derivation, authenticated
//! decryption, protected values, and the database object model.

use std::io::Write;

use thiserror::Error;

pub use keepass::config::{
    CompressionConfig, DatabaseVersion, InnerCipherConfig, KdfConfig, OuterCipherConfig,
};
pub use keepass::db::{
    fields, Attachment, AttachmentMut, Database, DatabaseFormatError, DatabaseOpenError,
    DatabaseSaveError, Entry, EntryMut, Group, GroupMut, Value,
};
pub use keepass::DatabaseKey;

const KDBX3_AES_KDF_ROUNDS_FIELD: u8 = 6;
const KDBX4_KDF_PARAMETERS_FIELD: u8 = 11;
const KDBX4_AES_KDF_UUID: &[u8] = &[
    0xC9, 0xD9, 0xF3, 0x9A, 0x62, 0x8A, 0x44, 0x60, 0xBF, 0x74, 0x0D, 0x08, 0xC1, 0x8A, 0x4F, 0xEA,
];
const KDBX4_ARGON2D_UUID: &[u8] = &[
    0xEF, 0x63, 0x6D, 0xDF, 0x8C, 0x29, 0x44, 0x4B, 0x91, 0xF7, 0xA9, 0xA4, 0x03, 0xE3, 0x0A, 0x0C,
];
const KDBX4_ARGON2ID_UUID: &[u8] = &[
    0x9E, 0x29, 0x8B, 0x19, 0x56, 0xDB, 0x47, 0x73, 0xB2, 0x3D, 0xFC, 0x3E, 0xC6, 0xF0, 0xA1, 0xE6,
];

/// Resource ceilings applied to file-supplied KDF settings before derivation.
///
/// Raise these explicitly with [`open_with_kdf_limits`] only when opening a
/// trusted database that requires a higher work factor.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KdfLimits {
    /// Maximum memory requested by Argon2, in bytes.
    pub max_argon2_memory_bytes: u64,
    /// Maximum Argon2 iterations.
    pub max_argon2_iterations: u64,
    /// Maximum approximate Argon2 work in byte-passes (memory multiplied by iterations).
    pub max_argon2_work_bytes: u64,
    /// Maximum Argon2 parallelism lanes.
    pub max_argon2_parallelism: u32,
    /// Maximum AES-KDF rounds.
    pub max_aes_kdf_rounds: u64,
}

impl Default for KdfLimits {
    fn default() -> Self {
        Self {
            max_argon2_memory_bytes: 256 * 1024 * 1024,
            max_argon2_iterations: 50,
            max_argon2_work_bytes: 4 * 1024 * 1024 * 1024,
            max_argon2_parallelism: 4,
            max_aes_kdf_rounds: 100_000_000,
        }
    }
}

/// Errors opening or saving a KeePass database through this crate.
#[derive(Debug, Error)]
pub enum KdbxError {
    #[error(transparent)]
    Open(#[from] DatabaseOpenError),

    #[error(transparent)]
    Save(#[from] DatabaseSaveError),

    #[error("malformed KDBX header while checking KDF resource limits: {0}")]
    MalformedKdfHeader(&'static str),

    #[error("unsupported KDF in KDBX header")]
    UnsupportedKdf,

    #[error("invalid KDF parameters: {0}")]
    InvalidKdfParameters(&'static str),

    #[error(
        "KDF parameter {parameter} requests {requested}, exceeding the configured limit {limit}"
    )]
    KdfLimitExceeded {
        parameter: &'static str,
        requested: u64,
        limit: u64,
    },
}

pub type KdbxResult<T> = Result<T, KdbxError>;

/// Opens and decrypts a KeePass database from its KDBX bytes.
///
/// KDBX 3 and KDBX 4 are supported by the underlying implementation. The key
/// may contain a master password, key file, or both. File-supplied KDF
/// parameters are subject to [`KdfLimits::default`].
pub fn open(bytes: &[u8], key: DatabaseKey) -> KdbxResult<Database> {
    open_with_kdf_limits(bytes, key, KdfLimits::default())
}

/// Opens a database with caller-selected KDF resource ceilings.
pub fn open_with_kdf_limits(
    bytes: &[u8],
    key: DatabaseKey,
    limits: KdfLimits,
) -> KdbxResult<Database> {
    validate_kdf_limits(bytes, limits)?;
    Ok(Database::parse(bytes, key)?)
}

/// Serializes and encrypts a database as KDBX 4.
///
/// The underlying `keepass` crate currently describes KDBX 4 writing as
/// experimental. Do not rely on this for production data without validating
/// output against supported KeePass/KeePassXC versions and retaining backups.
pub fn save_kdbx4(
    database: &Database,
    key: DatabaseKey,
    destination: &mut dyn Write,
) -> KdbxResult<()> {
    Ok(database.save(destination, key)?)
}

fn validate_kdf_limits(bytes: &[u8], limits: KdfLimits) -> KdbxResult<()> {
    if bytes.len() < 12 {
        return Ok(());
    }
    let mut version_cursor = 8;
    let version = read_u32_le(bytes, &mut version_cursor)?;

    let major_version = (version >> 16) as u16;
    if major_version != 3 && major_version != 4 {
        return Ok(());
    }

    let mut cursor = 12;
    loop {
        let field_id = *bytes
            .get(cursor)
            .ok_or(KdbxError::MalformedKdfHeader("missing end-of-header field"))?;
        cursor += 1;

        let field_length = if major_version == 4 {
            usize::try_from(read_u32_le(bytes, &mut cursor)?)
                .map_err(|_| KdbxError::MalformedKdfHeader("field length overflow"))?
        } else {
            usize::from(read_u16_le(bytes, &mut cursor)?)
        };
        let end = cursor
            .checked_add(field_length)
            .ok_or(KdbxError::MalformedKdfHeader("field length overflow"))?;
        let value = bytes
            .get(cursor..end)
            .ok_or(KdbxError::MalformedKdfHeader("truncated header field"))?;
        cursor = end;

        if field_id == 0 {
            return Ok(());
        }

        if major_version == 3 && field_id == KDBX3_AES_KDF_ROUNDS_FIELD {
            let rounds = match value.len() {
                8 => decode_u64_le(value, "invalid AES-KDF rounds field")?,
                _ => {
                    return Err(KdbxError::MalformedKdfHeader(
                        "invalid AES-KDF rounds field",
                    ))
                }
            };
            if rounds == 0 {
                return Err(KdbxError::InvalidKdfParameters(
                    "AES-KDF rounds must be greater than zero",
                ));
            }
            enforce_limit("AES-KDF rounds", rounds, limits.max_aes_kdf_rounds)?;
        } else if major_version == 4 && field_id == KDBX4_KDF_PARAMETERS_FIELD {
            check_kdbx4_kdf_parameters(value, limits)?;
        }
    }
}

fn check_kdbx4_kdf_parameters(bytes: &[u8], limits: KdfLimits) -> KdbxResult<()> {
    let mut cursor = 0;
    let version = read_u16_le(bytes, &mut cursor)?;
    if version >> 8 > 1 {
        return Err(KdbxError::MalformedKdfHeader(
            "unsupported variant dictionary version",
        ));
    }

    let mut uuid = None;
    let mut aes_rounds = None;
    let mut argon_memory = None;
    let mut argon_iterations = None;
    let mut argon_parallelism = None;
    let mut kdf_salt_length = None;
    let mut argon_version = None;

    loop {
        let value_type = *bytes.get(cursor).ok_or(KdbxError::MalformedKdfHeader(
            "missing variant dictionary terminator",
        ))?;
        cursor += 1;
        if value_type == 0 {
            if cursor != bytes.len() {
                return Err(KdbxError::MalformedKdfHeader(
                    "unexpected data after variant dictionary terminator",
                ));
            }
            break;
        }

        let name_length = usize::try_from(read_u32_le(bytes, &mut cursor)?)
            .map_err(|_| KdbxError::MalformedKdfHeader("name length overflow"))?;
        let name_end = cursor
            .checked_add(name_length)
            .ok_or(KdbxError::MalformedKdfHeader("name length overflow"))?;
        let name = std::str::from_utf8(
            bytes
                .get(cursor..name_end)
                .ok_or(KdbxError::MalformedKdfHeader("truncated parameter name"))?,
        )
        .map_err(|_| KdbxError::MalformedKdfHeader("parameter name is not UTF-8"))?;
        cursor = name_end;

        let value_length = usize::try_from(read_u32_le(bytes, &mut cursor)?)
            .map_err(|_| KdbxError::MalformedKdfHeader("value length overflow"))?;
        let value_end = cursor
            .checked_add(value_length)
            .ok_or(KdbxError::MalformedKdfHeader("value length overflow"))?;
        let value = bytes
            .get(cursor..value_end)
            .ok_or(KdbxError::MalformedKdfHeader("truncated parameter value"))?;
        cursor = value_end;

        match (name, value_type) {
            ("$UUID", 0x42) => uuid = Some(value),
            ("R", 0x05) => aes_rounds = Some(decode_u64_le(value, "invalid AES-KDF rounds")?),
            ("M", 0x05) => {
                argon_memory = Some(decode_u64_le(value, "invalid Argon2 memory parameter")?)
            }
            ("I", 0x05) => {
                argon_iterations = Some(decode_u64_le(value, "invalid Argon2 iterations")?)
            }
            ("P", 0x04) => {
                argon_parallelism = Some(decode_u32_le(value, "invalid Argon2 parallelism")?)
            }
            ("S", 0x42) => kdf_salt_length = Some(value.len()),
            ("V", 0x04) => argon_version = Some(decode_u32_le(value, "invalid Argon2 version")?),
            _ => {}
        }
    }

    match uuid.ok_or(KdbxError::MalformedKdfHeader("missing KDF UUID"))? {
        KDBX4_AES_KDF_UUID => {
            if aes_rounds == Some(0) {
                return Err(KdbxError::InvalidKdfParameters(
                    "AES-KDF rounds must be greater than zero",
                ));
            }
            if kdf_salt_length != Some(32) {
                return Err(KdbxError::InvalidKdfParameters(
                    "AES-KDF seed must contain 32 bytes",
                ));
            }
            enforce_limit(
                "AES-KDF rounds",
                aes_rounds.ok_or(KdbxError::MalformedKdfHeader("missing AES-KDF rounds"))?,
                limits.max_aes_kdf_rounds,
            )
        }
        KDBX4_ARGON2D_UUID | KDBX4_ARGON2ID_UUID => {
            let memory =
                argon_memory.ok_or(KdbxError::MalformedKdfHeader("missing Argon2 memory"))?;
            let iterations = argon_iterations
                .ok_or(KdbxError::MalformedKdfHeader("missing Argon2 iterations"))?;
            let work = memory
                .checked_mul(iterations)
                .ok_or(KdbxError::MalformedKdfHeader("Argon2 work factor overflow"))?;
            let parallelism = argon_parallelism
                .ok_or(KdbxError::MalformedKdfHeader("missing Argon2 parallelism"))?;
            if !(8 * 1024..=0x7FFF_FFFF).contains(&memory)
                || iterations == 0
                || iterations > u64::from(u32::MAX)
                || parallelism == 0
                || parallelism > 0x00FF_FFFF
                || !matches!(argon_version, Some(0x10 | 0x13))
                || !matches!(kdf_salt_length, Some(8..=0x3FFF_FFFF))
            {
                return Err(KdbxError::InvalidKdfParameters(
                    "Argon2 parameters are outside the KDBX specification",
                ));
            }
            enforce_limit(
                "Argon2 work (memory-bytes × iterations)",
                work,
                limits.max_argon2_work_bytes,
            )?;
            enforce_limit(
                "Argon2 memory (bytes)",
                memory,
                limits.max_argon2_memory_bytes,
            )?;
            enforce_limit(
                "Argon2 iterations",
                iterations,
                limits.max_argon2_iterations,
            )?;
            enforce_limit(
                "Argon2 parallelism",
                u64::from(parallelism),
                u64::from(limits.max_argon2_parallelism),
            )
        }
        _ => Err(KdbxError::UnsupportedKdf),
    }
}

fn enforce_limit(parameter: &'static str, requested: u64, limit: u64) -> KdbxResult<()> {
    if requested > limit {
        return Err(KdbxError::KdfLimitExceeded {
            parameter,
            requested,
            limit,
        });
    }
    Ok(())
}

fn read_u16_le(bytes: &[u8], cursor: &mut usize) -> KdbxResult<u16> {
    let end = cursor
        .checked_add(2)
        .ok_or(KdbxError::MalformedKdfHeader("integer offset overflow"))?;
    let value = bytes
        .get(*cursor..end)
        .ok_or(KdbxError::MalformedKdfHeader("truncated integer"))?;
    *cursor = end;
    decode_u16_le(value, "truncated integer")
}

fn read_u32_le(bytes: &[u8], cursor: &mut usize) -> KdbxResult<u32> {
    let end = cursor
        .checked_add(4)
        .ok_or(KdbxError::MalformedKdfHeader("integer offset overflow"))?;
    let value = bytes
        .get(*cursor..end)
        .ok_or(KdbxError::MalformedKdfHeader("truncated integer"))?;
    *cursor = end;
    decode_u32_le(value, "truncated integer")
}

fn decode_u16_le(bytes: &[u8], error: &'static str) -> KdbxResult<u16> {
    let value = bytes
        .try_into()
        .map_err(|_| KdbxError::MalformedKdfHeader(error))?;
    Ok(u16::from_le_bytes(value))
}

fn decode_u32_le(bytes: &[u8], error: &'static str) -> KdbxResult<u32> {
    let value = bytes
        .try_into()
        .map_err(|_| KdbxError::MalformedKdfHeader(error))?;
    Ok(u32::from_le_bytes(value))
}

fn decode_u64_le(bytes: &[u8], error: &'static str) -> KdbxResult<u64> {
    let value = bytes
        .try_into()
        .map_err(|_| KdbxError::MalformedKdfHeader(error))?;
    Ok(u64::from_le_bytes(value))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_key() -> DatabaseKey {
        DatabaseKey::new().with_password("correct horse battery staple")
    }

    fn sample_database() -> Database {
        let mut database = Database::new();
        database.meta.database_name = Some("KeePass-Nexus test vault".to_string());

        let mut root = database.root_mut();
        let mut group = root.add_group();
        group.name = "Personal".to_string();

        let mut entry = group.add_entry();
        entry.set_unprotected(fields::TITLE, "Email");
        entry.set_unprotected(fields::USERNAME, "user@example.test");
        entry.set_protected(fields::PASSWORD, "secret-value");

        database
    }

    #[test]
    fn writes_and_reopens_a_kdbx4_database() {
        let database = sample_database();
        let mut encoded = Vec::new();

        save_kdbx4(&database, test_key(), &mut encoded).unwrap();

        let version = Database::get_version(&mut encoded.as_slice()).unwrap();
        assert!(matches!(version, DatabaseVersion::KDB4(_)));

        let reopened = open(&encoded, test_key()).unwrap();
        assert_eq!(reopened, database);
        assert_eq!(reopened.num_groups(), 2);
        assert_eq!(reopened.num_entries(), 1);
        let entry = reopened
            .entry(reopened.iter_all_entries().next().unwrap().id())
            .unwrap();
        assert_eq!(entry.get(fields::PASSWORD), Some("secret-value"));
        assert!(matches!(
            entry.fields.get(fields::PASSWORD),
            Some(Value::Protected(_))
        ));

        let xml = Database::get_xml(&mut encoded.as_slice(), test_key()).unwrap();
        assert!(!String::from_utf8_lossy(&xml).contains("secret-value"));
    }

    #[test]
    fn rejects_a_wrong_password() {
        let database = sample_database();
        let mut encoded = Vec::new();
        save_kdbx4(&database, test_key(), &mut encoded).unwrap();

        let wrong_key = DatabaseKey::new().with_password("incorrect password");
        assert!(open(&encoded, wrong_key).is_err());
    }

    #[test]
    fn rejects_tampered_kdbx4_data() {
        let database = sample_database();
        let mut encoded = Vec::new();
        save_kdbx4(&database, test_key(), &mut encoded).unwrap();

        let payload_start = encoded.len() / 2;
        encoded[payload_start] ^= 0x80;
        assert!(open(&encoded, test_key()).is_err());
    }

    #[test]
    fn enforces_kdf_resource_limits_before_key_derivation() {
        let limits = KdfLimits {
            max_argon2_memory_bytes: 1,
            ..KdfLimits::default()
        };
        let error = open_with_kdf_limits(
            include_bytes!("../tests/fixtures/kdbx4_argon2_aes.bin"),
            test_key(),
            limits,
        )
        .unwrap_err();
        assert!(matches!(
            error,
            KdbxError::KdfLimitExceeded {
                parameter: "Argon2 memory (bytes)",
                ..
            }
        ));
    }

    #[test]
    fn enforces_aes_kdf_round_limits_before_key_transformation() {
        let limits = KdfLimits {
            max_aes_kdf_rounds: 0,
            ..KdfLimits::default()
        };
        let error = open_with_kdf_limits(
            include_bytes!("../tests/fixtures/kdbx4_aes_kdf_aes_cipher.bin"),
            test_key(),
            limits,
        )
        .unwrap_err();
        assert!(matches!(
            error,
            KdbxError::KdfLimitExceeded {
                parameter: "AES-KDF rounds",
                ..
            }
        ));
    }
}
