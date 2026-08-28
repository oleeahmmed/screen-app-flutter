import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Category permission for non-admin users.
String vaultCategoryPermissionLabel(Map<String, dynamic> cat) {
  if (cat['can_admin'] == true) return 'Admin';
  final p = (cat['my_permission'] ?? '').toString().toLowerCase();
  if (p == 'edit' || p == 'admin' || cat['can_manage_entries'] == true) return 'Edit';
  if (p == 'view') return 'View';
  return '';
}

bool vaultCanEditCategory(Map<String, dynamic>? cat, {required bool isAdmin}) {
  if (cat == null) return false;
  if (isAdmin || cat['can_admin'] == true) return true;
  if (cat['can_manage_entries'] == true) return true;
  final p = (cat['my_permission'] ?? '').toString().toLowerCase();
  return p == 'edit' || p == 'admin';
}

IconData vaultEntryIcon(Map<String, dynamic> e) {
  final url = (e['url'] ?? '').toString();
  final user = (e['username'] ?? '').toString();
  if (url.isNotEmpty) return Icons.language_outlined;
  if (user.isNotEmpty) return Icons.key_outlined;
  return Icons.lock_outline;
}

Widget vaultRoleBadge({required bool isAdmin}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: (isAdmin ? AppTheme.featureVault : AppTheme.accent).withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
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
  return Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: (edit ? AppTheme.accent : AppTheme.textMuted).withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: (edit ? AppTheme.accent : AppTheme.textMuted).withValues(alpha: 0.35),
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: edit ? AppTheme.accent : AppTheme.textMuted,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    ),
  );
}
