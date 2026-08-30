import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Category permission for non-admin users.
String vaultCategoryPermissionLabel(Map<String, dynamic> cat) {
  if (cat['can_admin'] == true) return 'Admin';
  final p = (cat['my_permission'] ?? '').toString().toLowerCase();
  if (p == 'edit' || p == 'admin' || cat['can_manage_entries'] == true) return 'Can edit';
  if (p == 'view') return 'View only';
  return '';
}

bool vaultCanEditCategory(Map<String, dynamic>? cat, {required bool isAdmin}) {
  if (cat == null) return false;
  if (isAdmin || cat['can_admin'] == true) return true;
  if (cat['can_manage_entries'] == true) return true;
  final p = (cat['my_permission'] ?? '').toString().toLowerCase();
  return p == 'edit' || p == 'admin';
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

/// Entry edit/delete — API `can_edit` / `can_delete` only (never category grant).
bool vaultEntryCanEdit(
  Map<String, dynamic> entry, {
  bool isVaultAdmin = false,
  int? currentUserId,
}) {
  if (entry.containsKey('can_edit') || entry.containsKey('can_delete')) {
    return vaultApiFlag(entry['can_edit']) || vaultApiFlag(entry['can_delete']);
  }
  // No flags yet — hide actions until detail fetch returns permissions.
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
