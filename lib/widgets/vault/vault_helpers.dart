import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/app_toast.dart';

/// Allowed last-extensions for vault attachments (must match backend whitelist).
const vaultAllowedAttachmentExtensions = {
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'rtf', 'odt', 'ods', 'ppt', 'pptx',
  'txt', 'md', 'log', 'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'conf', 'cfg',
  'env', 'properties',
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp',
  'sql', 'py', 'rb', 'pl', 'lua', 'r', 'sh', 'bash', 'zsh', 'ps1', 'js', 'ts',
};

const vaultMaxAttachmentBytes = 10 * 1024 * 1024;
const vaultMaxAttachmentsPerEntry = 20;

bool vaultAttachmentFilenameAllowed(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return vaultAllowedAttachmentExtensions.contains(ext);
}

Future<List<Map<String, dynamic>>> pickVaultPendingFiles(
  BuildContext context, {
  int alreadyCount = 0,
}) async {
  final remaining = vaultMaxAttachmentsPerEntry - alreadyCount;
  if (remaining <= 0) {
    if (context.mounted) {
      AppToast.error(context, 'At most $vaultMaxAttachmentsPerEntry files per entry');
    }
    return const [];
  }
  final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
  if (result == null) return const [];
  final out = <Map<String, dynamic>>[];
  for (final f in result.files) {
    if (out.length >= remaining) break;
    if (!vaultAttachmentFilenameAllowed(f.name)) {
      if (context.mounted) AppToast.error(context, '${f.name}: file type not allowed');
      continue;
    }
    List<int>? bytes = f.bytes?.toList();
    if (bytes == null && f.path != null) {
      bytes = await File(f.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) continue;
    if (bytes.length > vaultMaxAttachmentBytes) {
      if (context.mounted) AppToast.error(context, '${f.name}: must be 10 MB or smaller');
      continue;
    }
    out.add({'filename': f.name, 'bytes': bytes});
  }
  return out;
}

Widget vaultPendingFilesPicker({
  required List<Map<String, dynamic>> pendingFiles,
  required VoidCallback onAdd,
  required void Function(int index) onRemove,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.attach_file, size: 16),
        label: Text(
          pendingFiles.isEmpty
              ? 'Add files (optional)'
              : '${pendingFiles.length} file${pendingFiles.length == 1 ? '' : 's'} to attach',
        ),
      ),
      if (pendingFiles.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < pendingFiles.length; i++)
                InputChip(
                  label: Text(
                    pendingFiles[i]['filename']?.toString() ?? 'file',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onDeleted: () => onRemove(i),
                ),
            ],
          ),
        ),
    ],
  );
}

String vaultCategoryPermissionLabel(Map<String, dynamic> cat) {
  if (cat['can_admin'] == true) return 'Admin';
  // Normal users (any category grant) are view-only in the Flutter app.
  final p = (cat['my_permission'] ?? '').toString().toLowerCase();
  if (p.isNotEmpty || cat['can_manage_entries'] == true) return 'View only';
  return '';
}

/// Add / rename / mutate category content — Flutter: vault admin/manager only.
bool vaultCanEditCategory(Map<String, dynamic>? cat, {required bool isAdmin}) {
  if (cat == null) return false;
  return isAdmin || cat['can_admin'] == true;
}

/// Parse API int ids that may arrive as int or string.
int? vaultParseId(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

/// Strict truthy check for API boolean fields (bool, 1, "true").
bool vaultApiFlag(dynamic value) =>
    value == true || value == 1 || value?.toString().toLowerCase() == 'true';

/// Merge category grant onto an entry map (view markers for UI).
Map<String, dynamic> vaultEntryWithCategoryPerm(
  Map<String, dynamic> entry,
  Map<String, dynamic>? category,
) {
  if (category == null) return Map<String, dynamic>.from(entry);
  final out = Map<String, dynamic>.from(entry);
  final p = (category['my_permission'] ?? '').toString().toLowerCase();
  if (p.isNotEmpty) out['category_my_permission'] = p;
  if (category['can_admin'] == true) {
    out['category_can_admin'] = true;
  }
  return out;
}

/// Full entry manage (name / URL / username / password / delete).
/// Vault admin/manager only — matches backend `can_edit_secrets` / `can_delete`.
bool vaultEntryCanEdit(
  Map<String, dynamic> entry, {
  bool isVaultAdmin = false,
  int? currentUserId,
}) {
  if (entry['can_edit_secrets'] == true || entry['can_delete'] == true) {
    return true;
  }
  return isVaultAdmin || entry['category_can_admin'] == true;
}

/// Notes + attachment add/remove — anyone with view access on entry/category.
/// Matches backend `can_edit_notes` / `can_edit_attachments`.
bool vaultEntryCanEditNotesAttachments(
  Map<String, dynamic> entry, {
  bool isVaultAdmin = false,
  int? currentUserId,
}) {
  if (isVaultAdmin || entry['category_can_admin'] == true) return true;
  if (entry['can_edit_notes'] == true || entry['can_edit_attachments'] == true) {
    return true;
  }
  if (entry['can_edit'] == true) return true;
  final p = (entry['category_my_permission'] ?? '').toString().toLowerCase();
  if (p == 'view' || p == 'edit' || p == 'admin') return true;
  // Shared-with-me / loaded entry without category grant still has view access.
  if (entry.containsKey('can_edit_notes')) {
    return entry['can_edit_notes'] == true;
  }
  return false;
}

/// Immersive vault context card (project → category breadcrumb).
Widget vaultContextBanner({
  required String projectName,
  String? customerName,
  required String categoryName,
  required String subtitle,
  IconData icon = Icons.folder_special_outlined,
}) {
  return vaultSurfaceCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            vaultIconBox(icon: Icons.shield_outlined, color: AppTheme.featureVault, size: 42, iconSize: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    projectName,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  if (customerName != null && customerName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      customerName,
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.9),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
        ),
        Row(
          children: [
            vaultIconBox(icon: icon, color: AppTheme.accent, size: 36, iconSize: 18, radius: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    categoryName,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppTheme.primaryBright.withValues(alpha: 0.95),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Vault / project picker header (category list step).
Widget vaultProjectHeader({
  required String projectName,
  String? customerName,
  required String subtitle,
}) {
  return vaultSurfaceCard(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                AppTheme.featureVault.withValues(alpha: 0.85),
                AppTheme.featureVault.withValues(alpha: 0.45),
              ],
            ),
          ),
          child: const Icon(Icons.shield_outlined, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                projectName,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              if (customerName != null && customerName.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  customerName,
                  style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 13),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppTheme.primaryBright.withValues(alpha: 0.95),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

IconData vaultEntryIcon(Map<String, dynamic> e) {
  final url = (e['url'] ?? '').toString();
  final user = (e['username'] ?? '').toString();
  if (url.isNotEmpty) return Icons.language_outlined;
  if (user.isNotEmpty) return Icons.key_outlined;
  return Icons.lock_outline_rounded;
}

Widget vaultSectionLabel(String text) {
  return Text(
    text.toUpperCase(),
    style: TextStyle(
      color: AppTheme.textMuted.withValues(alpha: 0.85),
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    ),
  );
}

/// Profile-style surface card (form sections).
Widget vaultSurfaceCard({
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(14),
}) {
  return Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.055),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

Widget vaultIconBox({
  required IconData icon,
  required Color color,
  double size = 44,
  double iconSize = 22,
  double radius = 14,
}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Icon(icon, color: color, size: iconSize),
  );
}

Widget vaultRoleBadge({required bool isAdmin}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: (isAdmin ? AppTheme.featureVault : AppTheme.accent).withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: (isAdmin ? AppTheme.featureVault : AppTheme.accent).withValues(alpha: 0.35),
      ),
    ),
    child: Text(
      isAdmin ? 'Admin' : 'Shared with you',
      style: TextStyle(
        color: isAdmin ? AppTheme.featureVault : AppTheme.accent,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

Widget vaultPermissionChip(String label, {bool edit = false}) {
  if (label.isEmpty) return const SizedBox.shrink();
  final color = edit ? AppTheme.accent : AppTheme.textMuted;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
  );
}
