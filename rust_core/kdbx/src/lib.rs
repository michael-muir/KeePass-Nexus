use std::collections::BTreeMap;
use std::io;
use std::str;

use roxmltree::Document;
use thiserror::Error;

const KEEPASS_SIG_1: u32 = 0x9AA2D903;
const KEEPASS_SIG_2: u32 = 0xB54BFB67;
const FILE_VERSION_3: u32 = 0x00030000;
const FILE_VERSION_4: u32 = 0x00040000;

#[derive(Debug, Error)]
pub enum KdbxError {
    #[error("I/O error: {0}")]
    Io(#[from] io::Error),

    #[error("input ended unexpectedly while reading the KDBX header")]
    UnexpectedEof,

    #[error("invalid signature: expected {expected:#010x} {expected2:#010x}, got {actual1:#010x} {actual2:#010x}")]
    InvalidSignature {
        expected: u32,
        expected2: u32,
        actual1: u32,
        actual2: u32,
    },

    #[error("unsupported KDBX version: {0}")]
    UnsupportedVersion(u32),

    #[error("invalid UTF-8 payload: {0}")]
    InvalidUtf8(#[from] str::Utf8Error),

    #[error("XML parse error: {0}")]
    XmlParse(String),

    #[error("payload is encrypted or not yet decrypted")]
    EncryptedPayload,
}

pub type KdbxResult<T> = Result<T, KdbxError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum KdbxVersion {
    Kdbx3,
    Kdbx4,
    Other(u32),
}

impl KdbxVersion {
    pub fn from_u32(version: u32) -> KdbxResult<Self> {
        match version {
            FILE_VERSION_3 => Ok(Self::Kdbx3),
            FILE_VERSION_4 => Ok(Self::Kdbx4),
            _ if version >= FILE_VERSION_3 && version < FILE_VERSION_4 => Ok(Self::Kdbx3),
            _ if version >= FILE_VERSION_4 => Ok(Self::Kdbx4),
            _ => Err(KdbxError::UnsupportedVersion(version)),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KdbxHeader {
    pub signature_1: u32,
    pub signature_2: u32,
    pub version: u32,
    pub file_version: KdbxVersion,
    pub fields: BTreeMap<u8, Vec<u8>>,
    pub payload_offset: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KdbxFile {
    pub header: KdbxHeader,
    pub payload: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KdbxXmlSummary {
    pub database_name: Option<String>,
    pub group_count: usize,
    pub entry_count: usize,
    pub root_elements: Vec<String>,
}

impl KdbxFile {
    pub fn from_bytes(bytes: &[u8]) -> KdbxResult<Self> {
        let mut cursor = 0;

        let signature_1 = read_u32_le(bytes, &mut cursor)?;
        let signature_2 = read_u32_le(bytes, &mut cursor)?;

        if signature_1 != KEEPASS_SIG_1 || signature_2 != KEEPASS_SIG_2 {
            return Err(KdbxError::InvalidSignature {
                expected: KEEPASS_SIG_1,
                expected2: KEEPASS_SIG_2,
                actual1: signature_1,
                actual2: signature_2,
            });
        }

        let version = read_u32_le(bytes, &mut cursor)?;
        let file_version = KdbxVersion::from_u32(version)?;

        let mut fields = BTreeMap::new();
        let mut payload_offset = 0usize;

        loop {
            if cursor >= bytes.len() {
                return Err(KdbxError::UnexpectedEof);
            }

            let field_id = bytes[cursor];
            cursor += 1;

            if field_id == 0x00 {
                payload_offset = cursor;
                break;
            }

            let field_length = read_u32_le(bytes, &mut cursor)?;
            let end = cursor
                .checked_add(field_length as usize)
                .ok_or(KdbxError::UnexpectedEof)?;

            if end > bytes.len() {
                return Err(KdbxError::UnexpectedEof);
            }

            let field_data = bytes[cursor..end].to_vec();
            cursor = end;
            fields.insert(field_id, field_data);
        }

        let payload = bytes.get(payload_offset..).unwrap_or_default().to_vec();

        Ok(Self {
            header: KdbxHeader {
                signature_1,
                signature_2,
                version,
                file_version,
                fields,
                payload_offset,
            },
            payload,
        })
    }

    pub fn payload_summary(&self) -> KdbxResult<KdbxXmlSummary> {
        if self.payload.is_empty() {
            return Ok(KdbxXmlSummary {
                database_name: None,
                group_count: 0,
                entry_count: 0,
                root_elements: Vec::new(),
            });
        }

        let view = str::from_utf8(&self.payload)?;
        if !view.trim_start().starts_with('<') {
            return Err(KdbxError::EncryptedPayload);
        }

        let doc = Document::parse(view).map_err(|err| KdbxError::XmlParse(err.to_string()))?;
        let root = doc.root_element();
        let mut root_elements = Vec::new();
        for child in root.children() {
            root_elements.push(child.tag_name().name().to_string());
        }

        let group_count = doc
            .descendants()
            .filter(|node| node.tag_name().name() == "Group")
            .count();

        let entry_count = doc
            .descendants()
            .filter(|node| node.tag_name().name() == "Entry")
            .count();

        let database_name = doc
            .descendants()
            .find(|node| node.tag_name().name() == "Name")
            .and_then(|node| node.text())
            .map(str::to_string);

        Ok(KdbxXmlSummary {
            database_name,
            group_count,
            entry_count,
            root_elements,
        })
    }
}

fn read_u32_le(bytes: &[u8], cursor: &mut usize) -> KdbxResult<u32> {
    if *cursor + 4 > bytes.len() {
        return Err(KdbxError::UnexpectedEof);
    }

    let value = u32::from_le_bytes([
        bytes[*cursor],
        bytes[*cursor + 1],
        bytes[*cursor + 2],
        bytes[*cursor + 3],
    ]);
    *cursor += 4;
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_valid_kdbx_header() {
        let mut file = Vec::new();
        file.extend_from_slice(&KEEPASS_SIG_1.to_le_bytes());
        file.extend_from_slice(&KEEPASS_SIG_2.to_le_bytes());
        file.extend_from_slice(&FILE_VERSION_4.to_le_bytes());
        file.push(0x00);
        file.extend_from_slice(b"<KeePassFile><Root><Group><Entry/></Group></Root></KeePassFile>");

        let parsed = KdbxFile::from_bytes(&file).unwrap();
        assert_eq!(parsed.header.signature_1, KEEPASS_SIG_1);
        assert_eq!(parsed.header.signature_2, KEEPASS_SIG_2);
        assert_eq!(parsed.header.version, FILE_VERSION_4);
        assert_eq!(parsed.header.file_version, KdbxVersion::Kdbx4);
        assert!(parsed.payload.starts_with(b"<KeePassFile>"));
    }

    #[test]
    fn rejects_invalid_signatures() {
        let mut invalid = Vec::new();
        invalid.extend_from_slice(&0u32.to_le_bytes());
        invalid.extend_from_slice(&0u32.to_le_bytes());
        invalid.extend_from_slice(&FILE_VERSION_4.to_le_bytes());
        invalid.push(0x00);

        let err = KdbxFile::from_bytes(&invalid).unwrap_err();
        assert!(matches!(err, KdbxError::InvalidSignature { .. }));
    }

    #[test]
    fn parses_cleartext_xml_payload_summary() {
        let xml = r#"<KeePassFile><Root><Group><Name>Root</Name><Entry/><Entry/></Group></Root></KeePassFile>"#;
        let mut file = Vec::new();
        file.extend_from_slice(&KEEPASS_SIG_1.to_le_bytes());
        file.extend_from_slice(&KEEPASS_SIG_2.to_le_bytes());
        file.extend_from_slice(&FILE_VERSION_4.to_le_bytes());
        file.push(0x00);
        file.extend_from_slice(xml.as_bytes());

        let parsed = KdbxFile::from_bytes(&file).unwrap();
        let summary = parsed.payload_summary().unwrap();
        assert_eq!(summary.group_count, 1);
        assert_eq!(summary.entry_count, 2);
        assert_eq!(summary.database_name, Some("Root".to_string()));
    }
}
