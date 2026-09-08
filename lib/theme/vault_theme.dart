import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'app_theme.dart';

/// aims-webapps ProjectVault.jsx visual language for Flutter vault screens.
abstract final class VaultTheme {
  static const pageBg = AppTheme.immersivePageBg;
  static const panelBg = Color(0xFF111B21);
  static const modalBg = Color(0xFF1F2C34);

  static const violet = Color(0xFFA78BFA);
  static const violetBright = Color(0xFFC4B5FD);
  static const violetDeep = Color(0xFF8B5CF6);

  static const sharedBlue = Color(0xFF60A5FA);
  static const sharedBlueBright = Color(0xFF93C5FD);

  static const emerald = Color(0xFF34D399);

  static BoxDecoration glassPanel({double radius = 20}) => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      );

  static BoxDecoration cardSurface({bool accentViolet = true}) => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      );

  /// Premium project tile on the vault hub grid.
  static BoxDecoration projectHubCard({bool admin = false}) => BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: admin ? 0.09 : 0.07),
            violet.withValues(alpha: admin ? 0.12 : 0.05),
          ],
        ),
        border: Border.all(
          color: (admin ? violetBright : Colors.white).withValues(alpha: admin ? 0.28 : 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: violet.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      );

  static Widget topTab({
    required String label,
    required IconData icon,
    required bool active,
    required bool sharedTone,
    required VoidCallback onTap,
    int? badge,
  }) {
    final color = sharedTone ? sharedBlueBright : violetBright;
    final bg = sharedTone
        ? sharedBlue.withValues(alpha: active ? 0.15 : 0)
        : violet.withValues(alpha: active ? 0.15 : 0);
    final border = sharedTone
        ? sharedBlue.withValues(alpha: active ? 0.3 : 0)
        : violet.withValues(alpha: active ? 0.3 : 0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: (sharedTone ? sharedBlue : violet).withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: active ? color : AppTheme.textMuted),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: active ? color : AppTheme.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (badge != null && badge > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: sharedBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sharedBlue.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      color: sharedBlueBright,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget filterBar({
    required String active,
    required ValueChanged<String> onChanged,
    required int allCount,
    required int createdCount,
    required int sharedCount,
  }) {
    Widget pill(String id, String label, IconData? icon, int count, {bool blue = false}) {
      final selected = active == id;
      final color = blue ? sharedBlueBright : violetBright;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(id),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? (blue ? sharedBlue : violet).withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? (blue ? sharedBlue : violet).withValues(alpha: 0.3)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: selected ? color : AppTheme.textMuted),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? color : AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? (blue ? sharedBlue : violet).withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: selected ? color : AppTheme.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            pill('all', 'All', null, allCount),
            const SizedBox(width: 4),
            pill('created-by-me', 'Created by me', LucideIcons.userCheck, createdCount),
            const SizedBox(width: 4),
            pill('shared-to-me', 'Shared to me', LucideIcons.share2, sharedCount, blue: true),
          ],
        ),
      ),
    );
  }

  static Widget createdByBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: violet.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: violet.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.userCheck, size: 10, color: violetBright),
          const SizedBox(width: 4),
          Text(
            'Created by me',
            style: TextStyle(
              color: violetBright,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static Widget sharedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: sharedBlue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: sharedBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.share2, size: 10, color: sharedBlueBright),
          const SizedBox(width: 4),
          Text(
            'Shared',
            style: TextStyle(
              color: sharedBlueBright,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static Widget iconBox({
    required IconData icon,
    required Color color,
    double size = 40,
    double iconSize = 18,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }

  static Widget searchField({
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.75), fontSize: 14),
        prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textMuted.withValues(alpha: 0.9), size: 20),
        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.07),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: violet.withValues(alpha: 0.45)),
        ),
      ),
    );
  }

  static Widget letterPicker({
    required String? active,
    required ValueChanged<String?> onChanged,
  }) {
    final letters = ['#', ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: letters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) {
          final letter = letters[i];
          final selected = active == letter;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onChanged(selected ? null : letter),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? violet.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? violet.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Text(
                  letter,
                  style: TextStyle(
                    color: selected ? violetBright : AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static int? entryCreatorId(Map<String, dynamic> entry) {
    final raw = entry['created_by'] ?? entry['created_by_id'] ?? entry['user_id'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  static bool isCreatedByMe(Map<String, dynamic> item, int? myUserId) {
    if (myUserId == null) return false;
    final creator = entryCreatorId(item);
    if (creator == null) {
      final alt = item['created_by'];
      if (alt is Map) {
        final id = alt['id'];
        if (id is int) return id == myUserId;
        return int.tryParse('$id') == myUserId;
      }
      return false;
    }
    return creator == myUserId;
  }
}
