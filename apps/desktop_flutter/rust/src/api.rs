use std::io::Cursor;

use chrono::{DateTime, NaiveDateTime, SecondsFormat, Timelike, Utc};
use kdbx::{
    fields, DatabaseKey, DatabaseVersion, EntryId, EntryMut, EntryTrack, GroupId, Icon,
    KdbxDatabase, Value,
};
use uuid::Uuid;
use zeroize::Zeroize;

const MAX_CUSTOM_ICON_BYTES: usize = 1024 * 1024;
const MAX_ATTACHMENT_BYTES: usize = 25 * 1024 * 1024;
const FAVORITE_KEY: &str = "KeePassNexus.Favorite";

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
    pub is_recycle_bin: bool,
    pub parent_is_recycle_bin: bool,
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
    pub tags: Vec<String>,
    pub favorite: bool,
    pub expires: bool,
    pub expires_at: Option<String>,
    pub modified_at: Option<String>,
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
    pub tags: Vec<String>,
    pub favorite: bool,
    pub expires: bool,
    pub expires_at: Option<String>,
    pub custom_fields: Vec<CustomField>,
    pub attachments: Vec<EntryAttachment>,
    pub history_count: usize,
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
    pub tags: Vec<String>,
    pub favorite: bool,
    pub expires: bool,
    pub expires_at: Option<String>,
    pub custom_fields: Vec<CustomField>,
    pub attachments: Vec<EntryAttachment>,
}

#[derive(Clone, Debug)]
pub struct CustomField {
    pub name: String,
    pub value: String,
    pub protected: bool,
}

#[derive(Clone, Debug)]
pub struct EntryAttachment {
    pub name: String,
    pub data: Vec<u8>,
}

#[derive(Clone, Debug)]
pub struct EntryHistoryItem {
    pub index: usize,
    pub title: String,
    pub username: String,
    pub modified_at: Option<String>,
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
        tags: entry.tags.clone(),
        favorite: is_favorite(&entry),
        expires: entry.times.expires.unwrap_or(false),
        expires_at: format_expiry(entry.times.expiry),
        custom_fields: entry
            .fields
            .iter()
            .filter(|(name, _)| !is_standard_field(name))
            .map(|(name, value)| CustomField {
                name: name.clone(),
                value: value.get().clone(),
                protected: value.is_protected(),
            })
            .collect(),
        attachments: entry
            .attachments_named()
            .map(|(name, attachment)| EntryAttachment {
                name: name.to_string(),
                data: attachment.data.get().clone(),
            })
            .collect(),
        history_count: entry
            .history
            .as_ref()
            .map_or(0, |history| history.get_entries().len()),
    })
}

pub fn entry_history(session: &VaultSession, id: String) -> Result<Vec<EntryHistoryItem>, String> {
    let id = parse_entry_id(&id)?;
    let entry = session
        .database
        .read_entry(id)
        .map_err(|error| error.to_string())?;
    Ok(entry
        .history
        .as_ref()
        .into_iter()
        .flat_map(|history| history.get_entries().iter().enumerate())
        .map(|(index, historical)| EntryHistoryItem {
            index,
            title: historical
                .get(fields::TITLE)
                .unwrap_or_default()
                .to_string(),
            username: historical
                .get(fields::USERNAME)
                .unwrap_or_default()
                .to_string(),
            modified_at: format_expiry(historical.times.last_modification),
        })
        .collect())
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
                &summary.tags.join(" "),
            ]
            .iter()
            .any(|value| value.to_lowercase().contains(&query))
            .then_some(summary)
        })
        .collect())
}

pub fn entries_by_tag(session: &VaultSession, tag: String) -> Result<Vec<EntrySummary>, String> {
    let normalized = tag.to_lowercase();
    Ok(session
        .database
        .database()
        .iter_all_entries()
        .filter(|entry| {
            entry
                .tags
                .iter()
                .any(|item| item.to_lowercase() == normalized)
        })
        .map(entry_summary)
        .collect())
}

pub fn favorite_entries(session: &VaultSession) -> Result<Vec<EntrySummary>, String> {
    Ok(session
        .database
        .database()
        .iter_all_entries()
        .filter(|entry| is_favorite(entry))
        .map(entry_summary)
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

pub fn rename_group(session: &mut VaultSession, id: String, name: String) -> Result<(), String> {
    let id = parse_group_id(&id)?;
    if id == session.database.database().root().id() {
        return Err("The root group cannot be renamed.".to_string());
    }
    session
        .database
        .update_group(id, |group| group.name = name.trim().to_string())
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(())
}

pub fn move_group(session: &mut VaultSession, id: String, parent_id: String) -> Result<(), String> {
    let id = parse_group_id(&id)?;
    let parent_id = parse_group_id(&parent_id)?;
    if id == session.database.database().root().id() {
        return Err("The root group cannot be moved.".to_string());
    }
    let mut group = session
        .database
        .database_mut()
        .group_mut(id)
        .ok_or_else(|| "Group does not exist.".to_string())?;
    group
        .move_to(parent_id)
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(())
}

pub fn delete_group(session: &mut VaultSession, id: String) -> Result<(), String> {
    let id = parse_group_id(&id)?;
    let root_id = session.database.database().root().id();
    if id == root_id {
        return Err("The root group cannot be deleted.".to_string());
    }
    let recycle_bin_id = ensure_recycle_bin(session)?;
    if id == recycle_bin_id {
        return Err("The recycle bin cannot be moved to itself.".to_string());
    }
    let mut group = session
        .database
        .database_mut()
        .group_mut(id)
        .ok_or_else(|| "Group does not exist.".to_string())?;
    group
        .move_to(recycle_bin_id)
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(())
}

pub fn restore_group(session: &mut VaultSession, id: String) -> Result<(), String> {
    let id = parse_group_id(&id)?;
    let recycle_bin_id = session
        .database
        .database()
        .recycle_bin()
        .map(|group| group.id())
        .ok_or_else(|| "The recycle bin does not exist.".to_string())?;
    let group = session
        .database
        .read_group(id)
        .map_err(|error| error.to_string())?;
    if group.parent().map(|parent| parent.id()) != Some(recycle_bin_id) {
        return Err("Only groups in the recycle bin can be restored.".to_string());
    }
    let parent_id = group
        .previous_parent()
        .map(|parent| parent.id())
        .filter(|parent_id| *parent_id != recycle_bin_id)
        .unwrap_or_else(|| session.database.database().root().id());
    drop(group);
    let mut group = session
        .database
        .database_mut()
        .group_mut(id)
        .ok_or_else(|| "Group does not exist.".to_string())?;
    group
        .move_to(parent_id)
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(())
}

pub fn permanently_delete_group(session: &mut VaultSession, id: String) -> Result<(), String> {
    let id = parse_group_id(&id)?;
    if id == session.database.database().root().id() {
        return Err("The root group cannot be permanently deleted.".to_string());
    }
    if session
        .database
        .database()
        .recycle_bin()
        .is_some_and(|bin| bin.id() == id)
    {
        return Err("The recycle bin itself cannot be permanently deleted.".to_string());
    }
    let bin_id = session
        .database
        .database()
        .recycle_bin()
        .map(|bin| bin.id())
        .ok_or_else(|| "The recycle bin does not exist.".to_string())?;
    let group = session
        .database
        .read_group(id)
        .map_err(|error| error.to_string())?;
    if !is_group_within_recycle_bin(&group, bin_id) {
        return Err("Only groups in the recycle bin can be permanently deleted.".to_string());
    }
    drop(group);
    session
        .database
        .delete_group(id)
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(())
}

pub fn create_entry(
    session: &mut VaultSession,
    group_id: String,
    input: EntryInput,
) -> Result<String, String> {
    validate_entry_input(&input)?;
    let expiry = parse_expiry(input.expires_at.as_deref())?;
    let group_id = parse_group_id(&group_id)?;
    let id = session
        .database
        .create_entry(group_id, |entry| set_entry_fields(entry, input, expiry))
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(id.to_string())
}

pub fn clone_entry(session: &mut VaultSession, id: String) -> Result<String, String> {
    let id = parse_entry_id(&id)?;
    let source = session
        .database
        .read_entry(id)
        .map_err(|error| error.to_string())?;
    let group_id = source.parent().id();
    let copied_fields = source.fields.clone();
    let tags = source.tags.clone();
    let times = source.times.clone();
    let custom_data = source.custom_data.clone();
    let foreground_color = source.foreground_color.clone();
    let background_color = source.background_color.clone();
    let override_url = source.override_url.clone();
    let attachments = source
        .attachments_named()
        .map(|(name, attachment)| (name.to_string(), attachment.data.clone()))
        .collect::<Vec<_>>();
    let current = session
        .database
        .read_entry(id)
        .map_err(|error| error.to_string())?;
    for (name, attachment) in current.attachments_named() {
        if !attachments.iter().any(|(old_name, old_data)| {
            old_name.eq_ignore_ascii_case(name) && old_data.get() == attachment.data.get()
        }) {
            return Err(
                "This history revision has different attachments; restoring it could damage older history."
                    .to_string(),
            );
        }
    }
    drop(current);
    let icon_id = match source.icon() {
        Some(Icon::BuiltIn(id)) => Some(*id),
        _ => None,
    };
    let icon_data = source.custom_icon().map(|icon| icon.data.clone());
    let cloned_id = session
        .database
        .database_mut()
        .group_mut(group_id)
        .ok_or_else(|| "Entry's parent group does not exist.".to_string())?
        .add_entry()
        .id();
    let mut cloned = session
        .database
        .database_mut()
        .entry_mut(cloned_id)
        .ok_or_else(|| "Unable to create the cloned entry.".to_string())?;
    cloned.fields = copied_fields;
    cloned.tags = tags;
    cloned.custom_data = custom_data;
    cloned.foreground_color = foreground_color;
    cloned.background_color = background_color;
    cloned.override_url = override_url;
    cloned.times.expires = times.expires;
    cloned.times.expiry = times.expiry;
    let cloned_title = format!("{} (copy)", cloned.get(fields::TITLE).unwrap_or_default());
    cloned.set_unprotected(fields::TITLE, cloned_title);
    if let Some(icon_data) = icon_data {
        cloned.set_icon_custom_new(icon_data).last_modification_time = Some(utc_now_naive());
    } else if let Some(icon_id) = icon_id {
        cloned.set_icon_builtin(icon_id);
    }
    for (name, data) in attachments {
        cloned.add_attachment(name, data);
    }
    session.dirty = true;
    Ok(cloned_id.to_string())
}

pub fn update_entry(
    session: &mut VaultSession,
    id: String,
    input: EntryInput,
) -> Result<(), String> {
    validate_entry_input(&input)?;
    let expiry = parse_expiry(input.expires_at.as_deref())?;
    let id = parse_entry_id(&id)?;
    validate_attachment_update(&session.database, id, &input.attachments)?;
    session
        .database
        .update_entry(id, |entry| set_entry_fields(entry, input, expiry))
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
    let bin_id = ensure_recycle_bin(session)?;
    let entry = session
        .database
        .read_entry(id)
        .map_err(|error| error.to_string())?;
    if entry.parent().id() == bin_id {
        session
            .database
            .delete_entry(id)
            .map_err(|error| error.to_string())?;
    } else {
        session
            .database
            .move_entry(id, bin_id)
            .map_err(|error| error.to_string())?;
    }
    session.dirty = true;
    Ok(())
}

pub fn permanently_delete_entry(session: &mut VaultSession, id: String) -> Result<(), String> {
    let id = parse_entry_id(&id)?;
    let bin_id = session
        .database
        .database()
        .recycle_bin()
        .map(|bin| bin.id())
        .ok_or_else(|| "The recycle bin does not exist.".to_string())?;
    let entry = session
        .database
        .read_entry(id)
        .map_err(|error| error.to_string())?;
    if entry.parent().id() != bin_id {
        return Err("Only entries in the recycle bin can be permanently deleted.".to_string());
    }
    drop(entry);
    session
        .database
        .delete_entry(id)
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(())
}

pub fn restore_entry(session: &mut VaultSession, id: String) -> Result<(), String> {
    let id = parse_entry_id(&id)?;
    let recycle_bin_id = session
        .database
        .database()
        .recycle_bin()
        .map(|group| group.id())
        .ok_or_else(|| "The recycle bin does not exist.".to_string())?;
    let entry = session
        .database
        .read_entry(id)
        .map_err(|error| error.to_string())?;
    if entry.parent().id() != recycle_bin_id {
        return Err("Only entries in the recycle bin can be restored.".to_string());
    }
    let parent_id = entry
        .previous_parent()
        .map(|parent| parent.id())
        .filter(|parent_id| *parent_id != recycle_bin_id)
        .unwrap_or_else(|| session.database.database().root().id());
    session
        .database
        .move_entry(id, parent_id)
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(())
}

pub fn set_entry_favorite(
    session: &mut VaultSession,
    id: String,
    favorite: bool,
) -> Result<(), String> {
    let id = parse_entry_id(&id)?;
    session
        .database
        .update_entry(id, |entry| set_favorite(entry, favorite))
        .map_err(|error| error.to_string())?;
    session.dirty = true;
    Ok(())
}

pub fn restore_entry_history(
    session: &mut VaultSession,
    id: String,
    history_index: usize,
) -> Result<(), String> {
    let id = parse_entry_id(&id)?;
    let current = session
        .database
        .read_entry(id)
        .map_err(|error| error.to_string())?;
    let source = current
        .historical(history_index)
        .ok_or_else(|| "That history revision no longer exists.".to_string())?;
    let fields = source.fields.clone();
    let tags = source.tags.clone();
    let custom_data = source.custom_data.clone();
    let times = source.times.clone();
    let foreground_color = source.foreground_color.clone();
    let background_color = source.background_color.clone();
    let override_url = source.override_url.clone();
    let attachments = source
        .attachments_named()
        .map(|(name, attachment)| (name.to_string(), attachment.data.clone()))
        .collect::<Vec<_>>();
    let icon_id = match source.icon() {
        Some(Icon::BuiltIn(id)) => Some(*id),
        _ => None,
    };
    let icon_data = source.custom_icon().map(|icon| icon.data.clone());
    let mut entry = session
        .database
        .database_mut()
        .entry_mut(id)
        .ok_or_else(|| "Entry does not exist.".to_string())?;
    entry.fields = fields;
    entry.tags = tags;
    entry.custom_data = custom_data;
    entry.times.expires = times.expires;
    entry.times.expiry = times.expiry;
    entry.foreground_color = foreground_color;
    entry.background_color = background_color;
    entry.override_url = override_url;
    if let Some(icon_data) = icon_data {
        entry.set_icon_custom_new(icon_data).last_modification_time = Some(utc_now_naive());
    } else if let Some(icon_id) = icon_id {
        entry.set_icon_builtin(icon_id);
    } else {
        entry.set_icon_none();
    }
    for (name, data) in attachments {
        entry.add_attachment(name, data);
    }
    session.dirty = true;
    Ok(())
}

pub fn save_vault(
    session: &mut VaultSession,
    allow_kdbx_format_upgrade: bool,
) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    match &session.database.database().config.version {
        DatabaseVersion::KDB3(_) | DatabaseVersion::KDB4(0) if !allow_kdbx_format_upgrade => {
            return Err(
                "Saving this database requires explicit confirmation to upgrade its KDBX format."
                    .to_string(),
            );
        }
        DatabaseVersion::KDB3(_) | DatabaseVersion::KDB4(0) => {
            session
                .database
                .save_as_kdbx4(session.key.clone(), &mut bytes)
                .map_err(|error| error.to_string())?;
            session.database.database_mut().config.version = DatabaseVersion::KDB4(1);
        }
        _ => session
            .database
            .save_kdbx4(session.key.clone(), &mut bytes)
            .map_err(|error| error.to_string())?,
    }
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
    let mut groups = group.groups().map(build_group_node).collect::<Vec<_>>();
    groups.sort_by(|left, right| left.name.to_lowercase().cmp(&right.name.to_lowercase()));

    GroupNode {
        id: group.id().to_string(),
        name: group.name.clone(),
        is_recycle_bin: group
            .database()
            .recycle_bin()
            .is_some_and(|recycle_bin| recycle_bin.id() == group.id()),
        parent_is_recycle_bin: group.parent().is_some_and(|parent| {
            group
                .database()
                .recycle_bin()
                .is_some_and(|recycle_bin| recycle_bin.id() == parent.id())
        }),
        groups,
        entries,
    }
}

fn is_group_within_recycle_bin(group: &kdbx::GroupRef<'_>, recycle_bin_id: GroupId) -> bool {
    let database = group.database();
    let mut current = Some(group.id());
    while let Some(id) = current {
        if id == recycle_bin_id {
            return true;
        }
        current = database
            .group(id)
            .and_then(|current_group| current_group.parent().map(|parent| parent.id()));
    }
    false
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
        tags: entry.tags.clone(),
        favorite: is_favorite(&entry),
        expires: entry.times.expires.unwrap_or(false),
        expires_at: format_expiry(entry.times.expiry),
        modified_at: format_expiry(entry.times.last_modification),
    }
}

fn is_standard_field(name: &str) -> bool {
    matches!(
        name,
        fields::TITLE
            | fields::USERNAME
            | fields::PASSWORD
            | fields::URL
            | fields::NOTES
            | FAVORITE_KEY
    )
}

fn is_favorite(entry: &kdbx::EntryRef<'_>) -> bool {
    entry.get(FAVORITE_KEY) == Some("true")
}

fn set_favorite(entry: &mut EntryTrack<'_>, favorite: bool) {
    if favorite {
        entry.set_unprotected(FAVORITE_KEY, "true");
    } else {
        entry.as_mut().fields.remove(FAVORITE_KEY);
    }
}

fn utc_now_naive() -> NaiveDateTime {
    let now = Utc::now().naive_utc();
    now.with_nanosecond(0).expect("zero nanoseconds is valid")
}

fn ensure_recycle_bin(session: &mut VaultSession) -> Result<GroupId, String> {
    if let Some(bin) = session.database.database().recycle_bin() {
        return Ok(bin.id());
    }
    let root_id = session.database.database().root().id();
    let id = session
        .database
        .create_group(Some(root_id), |group| {
            group.name = "Recycle Bin".to_string()
        })
        .map_err(|error| error.to_string())?;
    let uuid = Uuid::parse_str(&id.to_string()).map_err(|error| error.to_string())?;
    let database = session.database.database_mut();
    database.meta.recyclebin_uuid = Some(uuid);
    database.meta.recyclebin_enabled = Some(true);
    database.meta.recyclebin_changed = Some(utc_now_naive());
    Ok(id)
}

fn parse_expiry(value: Option<&str>) -> Result<Option<NaiveDateTime>, String> {
    value
        .map(|value| {
            DateTime::parse_from_rfc3339(value)
                .map(|timestamp| timestamp.with_timezone(&Utc).naive_utc())
                .map_err(|error| format!("Invalid expiration timestamp: {error}"))
        })
        .transpose()
}

fn format_expiry(value: Option<NaiveDateTime>) -> Option<String> {
    value.map(|timestamp| {
        DateTime::<Utc>::from_naive_utc_and_offset(timestamp, Utc)
            .to_rfc3339_opts(SecondsFormat::Secs, true)
    })
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
    let mut names = std::collections::HashSet::new();
    for field in &input.custom_fields {
        if field.name.trim().is_empty() || is_standard_field(&field.name) {
            return Err(
                "Custom field names must be non-empty and not standard fields.".to_string(),
            );
        }
        if !names.insert(field.name.trim().to_lowercase()) {
            return Err("Custom field names must be unique.".to_string());
        }
    }
    names.clear();
    for attachment in &input.attachments {
        if attachment.name.trim().is_empty() {
            return Err("Attachment file names cannot be empty.".to_string());
        }
        if attachment.data.len() > MAX_ATTACHMENT_BYTES {
            return Err(format!(
                "Attachment exceeds the {MAX_ATTACHMENT_BYTES}-byte size limit."
            ));
        }
        if !names.insert(attachment.name.trim().to_lowercase()) {
            return Err("Attachment file names must be unique.".to_string());
        }
    }
    Ok(())
}

fn validate_attachment_update(
    database: &KdbxDatabase,
    id: EntryId,
    replacements: &[EntryAttachment],
) -> Result<(), String> {
    let entry = database.read_entry(id).map_err(|error| error.to_string())?;
    for (name, attachment) in entry.attachments_named() {
        let replacement = replacements
            .iter()
            .find(|item| item.name.eq_ignore_ascii_case(name));
        if !replacement.is_some_and(|item| item.data.as_slice() == attachment.data.get()) {
            return Err(
                "Removing or replacing attachments is not supported yet because the KDBX library cannot safely retain attachment history."
                    .to_string(),
            );
        }
    }
    Ok(())
}

trait EntryFieldSetter {
    fn set_plain(&mut self, key: &str, value: String);
    fn set_secret(&mut self, key: &str, value: String);
    fn set_icon(&mut self, icon_id: Option<u32>, icon_data: Vec<u8>);
    fn set_entry_metadata(
        &mut self,
        tags: Vec<String>,
        expires: bool,
        expires_at: Option<NaiveDateTime>,
    );
    fn set_extended_fields(
        &mut self,
        fields: Vec<CustomField>,
        attachments: Vec<EntryAttachment>,
        favorite: bool,
    );
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
            self.set_icon_custom_new(icon_data).last_modification_time = Some(utc_now_naive());
        } else if let Some(icon_id) = icon_id {
            self.set_icon_builtin(icon_id as usize);
        } else {
            self.set_icon_none();
        }
    }

    fn set_entry_metadata(
        &mut self,
        tags: Vec<String>,
        expires: bool,
        expires_at: Option<NaiveDateTime>,
    ) {
        self.tags = tags;
        self.times.expires = Some(expires);
        self.times.expiry = expires_at;
    }

    fn set_extended_fields(
        &mut self,
        fields: Vec<CustomField>,
        attachments: Vec<EntryAttachment>,
        favorite: bool,
    ) {
        self.fields.retain(|name, _| is_standard_field(name));
        for field in fields {
            let value = if field.protected {
                Value::protected(field.value)
            } else {
                Value::unprotected(field.value)
            };
            self.fields.insert(field.name.trim().to_string(), value);
        }
        let existing = self
            .as_ref()
            .attachments_named()
            .map(|(name, _)| name.to_string().to_lowercase())
            .collect::<Vec<_>>();
        for attachment in attachments {
            if existing.contains(&attachment.name.trim().to_lowercase()) {
                continue;
            }
            self.add_attachment(
                attachment.name.trim().to_string(),
                Value::unprotected(attachment.data),
            );
        }
        if favorite {
            self.set_unprotected(FAVORITE_KEY, "true");
        } else {
            self.fields.remove(FAVORITE_KEY);
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
            self.set_icon_custom_new(icon_data).last_modification_time = Some(utc_now_naive());
        } else if let Some(icon_id) = icon_id {
            self.set_icon_builtin(icon_id as usize);
        } else {
            self.set_icon_none();
        }
    }

    fn set_entry_metadata(
        &mut self,
        tags: Vec<String>,
        expires: bool,
        expires_at: Option<NaiveDateTime>,
    ) {
        self.tags = tags;
        self.times.expires = Some(expires);
        self.times.expiry = expires_at;
    }

    fn set_extended_fields(
        &mut self,
        fields: Vec<CustomField>,
        attachments: Vec<EntryAttachment>,
        favorite: bool,
    ) {
        let mut entry = self.as_mut();
        entry.set_extended_fields(fields, attachments, favorite);
    }
}

fn set_entry_fields(
    entry: &mut impl EntryFieldSetter,
    input: EntryInput,
    expiry: Option<NaiveDateTime>,
) {
    entry.set_plain(fields::TITLE, input.title);
    entry.set_plain(fields::USERNAME, input.username);
    entry.set_secret(fields::PASSWORD, input.password);
    entry.set_plain(fields::URL, input.url);
    entry.set_plain(fields::NOTES, input.notes);
    entry.set_icon(input.icon_id, input.icon_data);
    entry.set_entry_metadata(input.tags, input.expires, expiry);
    entry.set_extended_fields(input.custom_fields, input.attachments, input.favorite);
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
                tags: vec!["account".to_string(), "personal".to_string()],
                favorite: true,
                expires: true,
                expires_at: Some("2030-01-15T12:30:00Z".to_string()),
                custom_fields: vec![CustomField {
                    name: "Account ID".to_string(),
                    value: "12345".to_string(),
                    protected: false,
                }],
                attachments: vec![EntryAttachment {
                    name: "receipt.txt".to_string(),
                    data: b"receipt".to_vec(),
                }],
            },
        )
        .unwrap();

        let created = read_entry(&session, entry_id.clone()).unwrap();
        assert_eq!(created.password, "secret");
        assert_eq!(created.icon_id, Some(1));
        assert_eq!(created.tags, vec!["account", "personal"]);
        assert!(created.favorite);
        assert_eq!(created.custom_fields.len(), 1);
        assert_eq!(created.attachments[0].data, b"receipt");
        assert!(created.expires);
        assert_eq!(created.expires_at.as_deref(), Some("2030-01-15T12:30:00Z"));
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
                tags: vec!["work".to_string()],
                favorite: false,
                expires: false,
                expires_at: Some("2031-02-16T13:45:00Z".to_string()),
                custom_fields: vec![CustomField {
                    name: "Recovery code".to_string(),
                    value: "private".to_string(),
                    protected: true,
                }],
                attachments: vec![EntryAttachment {
                    name: "receipt.txt".to_string(),
                    data: b"receipt".to_vec(),
                }],
            },
        )
        .unwrap();
        let updated = read_entry(&session, entry_id.clone()).unwrap();
        assert_eq!(updated.icon_id, None);
        assert_eq!(updated.icon_data, vec![137, 80, 78, 71]);
        assert_eq!(updated.tags, vec!["work"]);
        assert!(!updated.favorite);
        assert_eq!(updated.custom_fields[0].value, "private");
        assert!(updated.custom_fields[0].protected);
        assert_eq!(updated.attachments[0].data, b"receipt");
        assert!(!updated.expires);
        assert_eq!(updated.expires_at.as_deref(), Some("2031-02-16T13:45:00Z"));

        let search_results = search_entries(&session, "work".to_string()).unwrap();
        assert_eq!(search_results.len(), 1);
        assert_eq!(search_results[0].icon_id, None);
        assert_eq!(search_results[0].icon_data, vec![137, 80, 78, 71]);
        assert_eq!(search_results[0].tags, vec!["work"]);
        assert!(search_entries(&session, "secret".to_string())
            .unwrap()
            .is_empty());

        let encrypted = save_vault(&mut session, false).unwrap();
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
        assert_eq!(entry.tags, vec!["work"]);
        assert!(!entry.expires);
        assert_eq!(entry.expires_at.as_deref(), Some("2031-02-16T13:45:00Z"));

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

        delete_entry(&mut session, entry_id.clone()).unwrap();
        assert_eq!(vault_snapshot(&session).unwrap().entry_count, 1);
        permanently_delete_entry(&mut session, entry_id).unwrap();
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
            tags: Vec::new(),
            favorite: false,
            expires: false,
            expires_at: None,
            custom_fields: Vec::new(),
            attachments: vec![EntryAttachment {
                name: "file.txt".to_string(),
                data: b"original".to_vec(),
            }],
        };
        assert!(validate_entry_input(&oversized).is_err());

        let invalid_builtin = EntryInput {
            icon_id: Some(69),
            icon_data: Vec::new(),
            ..oversized
        };
        assert!(validate_entry_input(&invalid_builtin).is_err());
    }

    #[test]
    fn expiry_timestamps_require_rfc3339_and_are_normalized_to_utc() {
        let parsed = parse_expiry(Some("2031-02-16T15:45:00-02:00")).unwrap();
        assert_eq!(
            format_expiry(parsed).as_deref(),
            Some("2031-02-16T17:45:00Z")
        );
        assert!(parse_expiry(Some("not a timestamp")).is_err());
    }

    #[test]
    fn favorites_clones_and_history_restore_preserve_entry_data() {
        let mut session = create_vault("Test".to_string(), "password".to_string());
        let root = vault_snapshot(&session).unwrap().root.id;
        let id = create_entry(
            &mut session,
            root.clone(),
            EntryInput {
                title: "Original".to_string(),
                username: "alice".to_string(),
                password: "first".to_string(),
                url: String::new(),
                notes: String::new(),
                icon_id: None,
                icon_data: Vec::new(),
                tags: vec!["personal".to_string()],
                favorite: true,
                expires: false,
                expires_at: None,
                custom_fields: vec![CustomField {
                    name: "Account".to_string(),
                    value: "one".to_string(),
                    protected: false,
                }],
                attachments: vec![EntryAttachment {
                    name: "file.txt".to_string(),
                    data: b"original".to_vec(),
                }],
            },
        )
        .unwrap();
        update_entry(
            &mut session,
            id.clone(),
            EntryInput {
                title: "Updated".to_string(),
                username: "alice".to_string(),
                password: "second".to_string(),
                url: String::new(),
                notes: String::new(),
                icon_id: None,
                icon_data: Vec::new(),
                tags: vec!["work".to_string()],
                favorite: false,
                expires: false,
                expires_at: None,
                custom_fields: Vec::new(),
                attachments: vec![EntryAttachment {
                    name: "file.txt".to_string(),
                    data: b"original".to_vec(),
                }],
            },
        )
        .unwrap();
        let history = entry_history(&session, id.clone()).unwrap();
        assert_eq!(history.len(), 1);
        restore_entry_history(&mut session, id.clone(), history[0].index).unwrap();
        let restored = read_entry(&session, id.clone()).unwrap();
        assert_eq!(restored.title, "Original");
        assert_eq!(restored.password, "first");
        assert!(restored.favorite);
        assert_eq!(restored.attachments[0].data, b"original");

        let clone_id = clone_entry(&mut session, id).unwrap();
        let cloned = read_entry(&session, clone_id).unwrap();
        assert_eq!(cloned.title, "Original (copy)");
        assert_eq!(cloned.password, "first");
        assert_eq!(cloned.attachments[0].data, b"original");
        assert_eq!(favorite_entries(&session).unwrap().len(), 2);
    }

    #[test]
    fn deletions_use_recycle_bin_and_restore_previous_parent() {
        let mut session = create_vault("Test".to_string(), "password".to_string());
        let root = vault_snapshot(&session).unwrap().root.id;
        let child = create_group(&mut session, root.clone(), "Child".to_string()).unwrap();
        let entry = create_entry(
            &mut session,
            child.clone(),
            EntryInput {
                title: "Entry".to_string(),
                username: String::new(),
                password: String::new(),
                url: String::new(),
                notes: String::new(),
                icon_id: None,
                icon_data: Vec::new(),
                tags: Vec::new(),
                favorite: false,
                expires: false,
                expires_at: None,
                custom_fields: Vec::new(),
                attachments: Vec::new(),
            },
        )
        .unwrap();
        delete_entry(&mut session, entry.clone()).unwrap();
        let bin = session
            .database
            .database()
            .recycle_bin()
            .expect("deleting an entry creates the recycle bin");
        assert_eq!(bin.entries().next().unwrap().id().to_string(), entry);
        restore_entry(&mut session, entry.clone()).unwrap();
        assert_eq!(read_entry(&session, entry.clone()).unwrap().group_id, child);

        delete_group(&mut session, parse_group_id(&child).unwrap().to_string()).unwrap();
        assert!(session
            .database
            .database()
            .recycle_bin()
            .unwrap()
            .groups()
            .any(|group| group.id().to_string() == child));
        restore_group(&mut session, child.clone()).unwrap();
        assert_eq!(
            session
                .database
                .read_group(parse_group_id(&child).unwrap())
                .unwrap()
                .parent()
                .unwrap()
                .id()
                .to_string(),
            root
        );
    }

    #[test]
    fn kdbx3_save_requires_explicit_conversion_and_emits_verified_kdbx4() {
        let bytes =
            include_bytes!("../../../../rust_core/kdbx/tests/fixtures/keepassxc_format300.kdbx")
                .to_vec();
        let mut session = open_vault(bytes, Some("a".to_string()), None).unwrap();
        assert!(save_vault(&mut session, false).is_err());

        let converted = save_vault(&mut session, true).unwrap();
        assert!(matches!(
            kdbx::Database::get_version(&mut converted.as_slice()).unwrap(),
            DatabaseVersion::KDB4(_)
        ));
        let reopened = open_vault(converted, Some("a".to_string()), None).unwrap();
        assert_eq!(
            vault_snapshot(&reopened).unwrap().name,
            "Test Database Format 0x00030000"
        );
    }

    #[test]
    fn kdbx4_0_save_requires_explicit_upgrade_to_4_1() {
        let bytes =
            include_bytes!("../../../../rust_core/kdbx/tests/fixtures/keepassxc_format400.kdbx")
                .to_vec();
        let mut session = open_vault(bytes, Some("t".to_string()), None).unwrap();
        assert!(save_vault(&mut session, false).is_err());

        let upgraded = save_vault(&mut session, true).unwrap();
        assert_eq!(
            kdbx::Database::get_version(&mut upgraded.as_slice()).unwrap(),
            DatabaseVersion::KDB4(1)
        );
        let reopened = open_vault(upgraded, Some("t".to_string()), None).unwrap();
        assert_eq!(vault_snapshot(&reopened).unwrap().name, "Format400");
        assert_eq!(reopened.database.database().num_attachments(), 1);
    }
}
