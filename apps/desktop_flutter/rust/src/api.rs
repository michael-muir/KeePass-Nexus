use std::io::Cursor;

use kdbx::{fields, DatabaseKey, EntryId, EntryMut, EntryTrack, GroupId, Icon, KdbxDatabase};
use uuid::Uuid;
use zeroize::Zeroize;

const MAX_CUSTOM_ICON_BYTES: usize = 1024 * 1024;

pub struct VaultSession {
    database: KdbxDatabase,
    key: DatabaseKey,
    dirty: bool,
}

#[derive(Clone, Debug)]
pub struct VaultSnapshot {
    pub name: String,
    pub root: GroupNode,
    pub entry_count: usize,
    pub group_count: usize,
    pub dirty: bool,
}

#[derive(Clone, Debug)]
pub struct GroupNode {
    pub id: String,
    pub name: String,
    pub groups: Vec<GroupNode>,
    pub entries: Vec<EntrySummary>,
}

#[derive(Clone, Debug)]
pub struct EntrySummary {
    pub id: String,
    pub group_id: String,
    pub title: String,
    pub username: String,
    pub url: String,
    pub notes: String,
    pub icon_id: Option<u32>,
    pub icon_data: Vec<u8>,
}

#[derive(Clone, Debug)]
pub struct EntryDetails {
    pub id: String,
    pub group_id: String,
    pub title: String,
    pub username: String,
    pub password: String,
    pub url: String,
    pub notes: String,
    pub icon_id: Option<u32>,
    pub icon_data: Vec<u8>,
}

#[derive(Clone, Debug)]
pub struct EntryInput {
    pub title: String,
    pub username: String,
    pub password: String,
    pub url: String,
    pub notes: String,
    pub icon_id: Option<u32>,
    pub icon_data: Vec<u8>,
}

pub fn open_vault(
    bytes: Vec<u8>,
    password: Option<String>,
    key_file: Option<Vec<u8>>,
) -> Result<VaultSession, String> {
    let key = build_key(password, key_file)?;
    let database = KdbxDatabase::open(&bytes, key.clone()).map_err(|error| error.to_string())?;
    Ok(VaultSession {
        database,
        key,
        dirty: false,
    })
}

pub fn create_vault(name: String, mut password: String) -> VaultSession {
    let mut database = KdbxDatabase::new();
    database.database_mut().meta.database_name = Some(name);
    let key = DatabaseKey::new().with_password(&password);
    password.zeroize();
    VaultSession {
        database,
        key,
        dirty: true,
    }
}

pub fn vault_snapshot(session: &VaultSession) -> Result<VaultSnapshot, String> {
    let database = session.database.database();
    let root = build_group_node(database.root());
    Ok(VaultSnapshot {
        name: database
            .meta
            .database_name
            .clone()
            .unwrap_or_else(|| "KeePass database".to_string()),
        root,
        entry_count: database.num_entries(),
        group_count: database.num_groups(),
        dirty: session.dirty,
    })
}

pub fn read_entry(session: &VaultSession, id: String) -> Result<EntryDetails, String> {
    let id = parse_entry_id(&id)?;
    let entry = session
        .database
        .read_entry(id)
        .map_err(|error| error.to_string())?;
    Ok(EntryDetails {
        id: id.to_string(),
        group_id: entry.parent().id().to_string(),
        title: entry.get(fields::TITLE).unwrap_or_default().to_string(),
        username: entry.get(fields::USERNAME).unwrap_or_default().to_string(),
        password: entry.get(fields::PASSWORD).unwrap_or_default().to_string(),
        url: entry.get(fields::URL).unwrap_or_default().to_string(),
        notes: entry.get(fields::NOTES).unwrap_or_default().to_string(),
        icon_id: match entry.icon() {
            Some(Icon::BuiltIn(id)) => u32::try_from(*id).ok(),
            _ => None,
        },
        icon_data: entry
            .custom_icon()
            .map(|icon| icon.data.clone())
            .unwrap_or_default(),
    })
}

pub fn search_entries(session: &VaultSession, query: String) -> Result<Vec<EntrySummary>, String> {
    let query = query.trim().to_lowercase();
    if query.is_empty() {
        return Ok(Vec::new());
    }

    Ok(session
        .database
        .database()
        .iter_all_entries()
        .filter_map(|entry| {
            let summary = entry_summary(entry);
            [
                &summary.title,
                &summary.username,
                &summary.url,
                &summary.notes,
            ]
            .iter()
            .any(|value| value.to_lowercase().contains(&query))
            .then_some(summary)
        })
        .collect())
}

pub fn create_group(
    session: &mut VaultSession,
    parent_id: String,
    name: String,
) -> Result<String, String> {
    let parent_id = parse_group_id(&parent_id)?;
    let id = session
        .database
        .create_group(Some(parent_id), |group| group.name = name)
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(id.to_string())
}

pub fn create_entry(
    session: &mut VaultSession,
    group_id: String,
    input: EntryInput,
) -> Result<String, String> {
    validate_entry_input(&input)?;
    let group_id = parse_group_id(&group_id)?;
    let id = session
        .database
        .create_entry(group_id, |entry| set_entry_fields(entry, input))
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(id.to_string())
}

pub fn update_entry(
    session: &mut VaultSession,
    id: String,
    input: EntryInput,
) -> Result<(), String> {
    validate_entry_input(&input)?;
    let id = parse_entry_id(&id)?;
    session
        .database
        .update_entry(id, |entry| set_entry_fields(entry, input))
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(())
}

pub fn move_entry(session: &mut VaultSession, id: String, group_id: String) -> Result<(), String> {
    let id = parse_entry_id(&id)?;
    let group_id = parse_group_id(&group_id)?;
    session
        .database
        .move_entry(id, group_id)
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(())
}

pub fn delete_entry(session: &mut VaultSession, id: String) -> Result<(), String> {
    let id = parse_entry_id(&id)?;
    session
        .database
        .delete_entry(id)
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(())
}

pub fn save_vault(session: &mut VaultSession) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    session
        .database
        .save_kdbx4(session.key.clone(), &mut bytes)
        .map_err(|error| error.to_string())?;
    Ok(bytes)
}

pub fn mark_vault_saved(session: &mut VaultSession) {
    session.dirty = false;
}

fn build_key(
    mut password: Option<String>,
    key_file: Option<Vec<u8>>,
) -> Result<DatabaseKey, String> {
    let mut key = DatabaseKey::new();
    if let Some(mut password) = password.take() {
        key = key.with_password(&password);
        password.zeroize();
    }
    if let Some(bytes) = key_file {
        key = key
            .with_keyfile(&mut Cursor::new(bytes))
            .map_err(|error| error.to_string())?;
    }
    Ok(key)
}

fn parse_group_id(value: &str) -> Result<GroupId, String> {
    Uuid::parse_str(value)
        .map(GroupId::from)
        .map_err(|error| format!("Invalid group ID: {error}"))
}

fn parse_entry_id(value: &str) -> Result<EntryId, String> {
    Uuid::parse_str(value)
        .map(EntryId::from)
        .map_err(|error| format!("Invalid entry ID: {error}"))
}

fn build_group_node(group: kdbx::GroupRef<'_>) -> GroupNode {
    let entries = group.entries().map(entry_summary).collect();
    let groups = group.groups().map(build_group_node).collect();

    GroupNode {
        id: group.id().to_string(),
        name: group.name.clone(),
        groups,
        entries,
    }
}

fn entry_summary(entry: kdbx::EntryRef<'_>) -> EntrySummary {
    EntrySummary {
        id: entry.id().to_string(),
        group_id: entry.parent().id().to_string(),
        title: entry.get(fields::TITLE).unwrap_or_default().to_string(),
        username: entry.get(fields::USERNAME).unwrap_or_default().to_string(),
        url: entry.get(fields::URL).unwrap_or_default().to_string(),
        notes: entry.get(fields::NOTES).unwrap_or_default().to_string(),
        icon_id: match entry.icon() {
            Some(Icon::BuiltIn(id)) => u32::try_from(*id).ok(),
            _ => None,
        },
        icon_data: entry
            .custom_icon()
            .map(|icon| icon.data.clone())
            .unwrap_or_default(),
    }
}

fn validate_entry_input(input: &EntryInput) -> Result<(), String> {
    if input.icon_data.len() > MAX_CUSTOM_ICON_BYTES {
        return Err(format!(
            "Custom icon exceeds the {MAX_CUSTOM_ICON_BYTES}-byte size limit."
        ));
    }
    if input.icon_data.is_empty() && input.icon_id.is_some_and(|id| id > 68) {
        return Err("Built-in icon ID is out of range.".to_string());
    }
    Ok(())
}

trait EntryFieldSetter {
    fn set_plain(&mut self, key: &str, value: String);
    fn set_secret(&mut self, key: &str, value: String);
    fn set_icon(&mut self, icon_id: Option<u32>, icon_data: Vec<u8>);
}

impl EntryFieldSetter for EntryMut<'_> {
    fn set_plain(&mut self, key: &str, value: String) {
        self.set_unprotected(key, value);
    }

    fn set_secret(&mut self, key: &str, value: String) {
        self.set_protected(key, value);
    }

    fn set_icon(&mut self, icon_id: Option<u32>, icon_data: Vec<u8>) {
        if !icon_data.is_empty() {
            self.set_icon_custom_new(icon_data);
        } else if let Some(icon_id) = icon_id {
            self.set_icon_builtin(icon_id as usize);
        } else {
            self.set_icon_none();
        }
    }
}

impl EntryFieldSetter for EntryTrack<'_> {
    fn set_plain(&mut self, key: &str, value: String) {
        self.set_unprotected(key, value);
    }

    fn set_secret(&mut self, key: &str, value: String) {
        self.set_protected(key, value);
    }

    fn set_icon(&mut self, icon_id: Option<u32>, icon_data: Vec<u8>) {
        if !icon_data.is_empty() {
            self.set_icon_custom_new(icon_data);
        } else if let Some(icon_id) = icon_id {
            self.set_icon_builtin(icon_id as usize);
        } else {
            self.set_icon_none();
        }
    }
}

fn set_entry_fields(entry: &mut impl EntryFieldSetter, input: EntryInput) {
    entry.set_plain(fields::TITLE, input.title);
    entry.set_plain(fields::USERNAME, input.username);
    entry.set_secret(fields::PASSWORD, input.password);
    entry.set_plain(fields::URL, input.url);
    entry.set_plain(fields::NOTES, input.notes);
    entry.set_icon(input.icon_id, input.icon_data);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vault_crud_round_trips_encrypted_entries() {
        let mut session = create_vault("Test vault".to_string(), "correct horse".to_string());
        let root_id = vault_snapshot(&session).unwrap().root.id;
        let group_id = create_group(&mut session, root_id.clone(), "Personal".to_string()).unwrap();
        let entry_id = create_entry(
            &mut session,
            group_id.clone(),
            EntryInput {
                title: "Email".to_string(),
                username: "user@example.test".to_string(),
                password: "secret".to_string(),
                url: "https://example.test".to_string(),
                notes: "Test account".to_string(),
                icon_id: Some(1),
                icon_data: Vec::new(),
            },
        )
        .unwrap();

        let created = read_entry(&session, entry_id.clone()).unwrap();
        assert_eq!(created.password, "secret");
        assert_eq!(created.icon_id, Some(1));
        update_entry(
            &mut session,
            entry_id.clone(),
            EntryInput {
                title: "Work email".to_string(),
                username: "user@example.test".to_string(),
                password: "updated-secret".to_string(),
                url: "https://example.test".to_string(),
                notes: "Updated account".to_string(),
                icon_id: None,
                icon_data: vec![137, 80, 78, 71],
            },
        )
        .unwrap();
        let updated = read_entry(&session, entry_id.clone()).unwrap();
        assert_eq!(updated.icon_id, None);
        assert_eq!(updated.icon_data, vec![137, 80, 78, 71]);

        let search_results = search_entries(&session, "account".to_string()).unwrap();
        assert_eq!(search_results.len(), 1);
        assert_eq!(search_results[0].icon_id, None);
        assert_eq!(search_results[0].icon_data, vec![137, 80, 78, 71]);
        assert!(search_entries(&session, "secret".to_string())
            .unwrap()
            .is_empty());

        let encrypted = save_vault(&mut session).unwrap();
        assert!(!encrypted
            .windows(b"updated-secret".len())
            .any(|window| window == b"updated-secret"));
        mark_vault_saved(&mut session);
        assert!(!vault_snapshot(&session).unwrap().dirty);

        let reopened = open_vault(encrypted, Some("correct horse".to_string()), None).unwrap();
        let entry = read_entry(&reopened, entry_id.clone()).unwrap();
        assert_eq!(entry.title, "Work email");
        assert_eq!(entry.password, "updated-secret");
        assert_eq!(entry.icon_id, None);
        assert_eq!(entry.icon_data, vec![137, 80, 78, 71]);

        let archive_group_id = create_group(&mut session, root_id, "Archive".to_string()).unwrap();
        move_entry(&mut session, entry_id.clone(), archive_group_id.clone()).unwrap();
        assert!(session
            .database
            .list_entries(parse_group_id(&group_id).unwrap())
            .unwrap()
            .is_empty());
        assert!(session
            .database
            .list_entries(parse_group_id(&archive_group_id).unwrap())
            .unwrap()
            .contains(&parse_entry_id(&entry_id).unwrap()));

        delete_entry(&mut session, entry_id).unwrap();
        assert_eq!(vault_snapshot(&session).unwrap().entry_count, 0);
    }

    #[test]
    fn entry_icon_inputs_are_size_and_id_checked() {
        let oversized = EntryInput {
            title: String::new(),
            username: String::new(),
            password: String::new(),
            url: String::new(),
            notes: String::new(),
            icon_id: None,
            icon_data: vec![0; MAX_CUSTOM_ICON_BYTES + 1],
        };
        assert!(validate_entry_input(&oversized).is_err());

        let invalid_builtin = EntryInput {
            icon_id: Some(69),
            icon_data: Vec::new(),
            ..oversized
        };
        assert!(validate_entry_input(&invalid_builtin).is_err());
    }
}
