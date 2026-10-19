import 'package:flutter/material.dart';

class EntryIconPreset {
  const EntryIconPreset(this.id, this.label, this.icon);

  final int id;
  final String label;
  final IconData icon;
}

const entryIconPresets = [
  EntryIconPreset(0, 'Key', Icons.key_outlined),
  EntryIconPreset(1, 'World', Icons.public),
  EntryIconPreset(2, 'Warning', Icons.warning_amber_rounded),
  EntryIconPreset(3, 'Server', Icons.dns_outlined),
  EntryIconPreset(4, 'Clipboard', Icons.assignment_outlined),
  EntryIconPreset(5, 'User', Icons.person_outline),
  EntryIconPreset(6, 'Settings', Icons.settings_outlined),
  EntryIconPreset(7, 'Notes', Icons.sticky_note_2_outlined),
  EntryIconPreset(8, 'Network', Icons.cloud_outlined),
  EntryIconPreset(9, 'Identity', Icons.badge_outlined),
  EntryIconPreset(10, 'Address book', Icons.contacts_outlined),
  EntryIconPreset(11, 'Camera', Icons.camera_alt_outlined),
  EntryIconPreset(12, 'Keys', Icons.key),
  EntryIconPreset(13, 'Plug', Icons.power_outlined),
  EntryIconPreset(14, 'Drive', Icons.storage_outlined),
  EntryIconPreset(15, 'Bookmark', Icons.bookmark_outline),
  EntryIconPreset(16, 'Disk', Icons.album_outlined),
  EntryIconPreset(17, 'Computer', Icons.desktop_windows_outlined),
  EntryIconPreset(18, 'Email', Icons.email_outlined),
  EntryIconPreset(19, 'Tools', Icons.build_outlined),
  EntryIconPreset(20, 'Checklist', Icons.fact_check_outlined),
  EntryIconPreset(21, 'Document', Icons.description_outlined),
  EntryIconPreset(22, 'Layout', Icons.dashboard_outlined),
  EntryIconPreset(23, 'Lightning', Icons.bolt_outlined),
  EntryIconPreset(24, 'Safe', Icons.security_outlined),
  EntryIconPreset(25, 'Save', Icons.save_outlined),
  EntryIconPreset(26, 'Terminal', Icons.terminal),
  EntryIconPreset(27, 'Printer', Icons.print_outlined),
  EntryIconPreset(28, 'Firewall', Icons.fireplace_outlined),
  EntryIconPreset(29, 'Wrench', Icons.handyman_outlined),
  EntryIconPreset(30, 'Folder', Icons.folder_outlined),
  EntryIconPreset(31, 'Clock', Icons.access_time),
  EntryIconPreset(32, 'Search', Icons.search),
  EntryIconPreset(33, 'Trash', Icons.delete_outline),
];

EntryIconPreset entryIconPreset(int? id) => entryIconPresets.firstWhere(
      (preset) => preset.id == id,
      orElse: () => entryIconPresets.first,
    );
