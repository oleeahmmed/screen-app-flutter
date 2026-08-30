import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/user_data_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_toast.dart';
import 'vault_helpers.dart';
import 'vault_sheets.dart';

/// Entry detail — reveal / copy / edit / delete / share (admin).
Future<void> showVaultEntryDetailSheet({
  required BuildContext context,
  required ApiService apiService,
  required int projectId,
  required Map<String, dynamic> entry,
  required bool isAdmin,
  required bool canEdit,
  required VoidCallback onChanged,
  int? currentUserId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppTheme.modalBarrierColor,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: AppTheme.surface2,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              VaultEntryDetailForm(
                apiService: apiService,
                projectId: projectId,
                entry: entry,
                isAdmin: isAdmin,
                canEdit: canEdit,
                currentUserId: currentUserId,
                onChanged: onChanged,
                embedded: false,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Profile-style credential form (sheet or full page).
class VaultEntryDetailForm extends StatefulWidget {
  final ApiService apiService;
  final int projectId;
  final Map<String, dynamic> entry;
  final bool isAdmin;
  final bool canEdit;
  final int? currentUserId;
  final VoidCallback onChanged;
  final bool embedded;

  const VaultEntryDetailForm({
    super.key,
    required this.apiService,
    required this.projectId,
    required this.entry,
    required this.isAdmin,
    required this.canEdit,
    required this.onChanged,
    this.currentUserId,
    this.embedded = false,
  });

  @override
  State<VaultEntryDetailForm> createState() => _VaultEntryDetailFormState();
}

class _VaultEntryDetailFormState extends State<VaultEntryDetailForm> {
  late Map<String, dynamic> _entry;
  String? _revealedPassword;
  Timer? _hideTimer;
  int? _currentUserId;
  bool _permissionsLoaded = false;

  int get _entryId => _entry['id'] as int;

  bool get _canManageEntry =>
      _permissionsLoaded &&
      vaultEntryCanEdit(
        _entry,
        isVaultAdmin: widget.isAdmin,
        currentUserId: _currentUserId ?? widget.currentUserId,
      );

  bool get _canShareEntry => _permissionsLoaded && widget.isAdmin;

  @override
  void initState() {
    super.initState();
    _entry = Map<String, dynamic>.from(widget.entry);
    _currentUserId = widget.currentUserId;
    _bootstrapUserAndFlags();
  }

  Future<void> _bootstrapUserAndFlags() async {
    final uidStr = await UserDataService.getUserId();
    final uid = int.tryParse(uidStr);
    if (!mounted) return;
    if (uid != null) {
      setState(() => _currentUserId = uid);
    }
    // Refresh can_edit from server so category-grant users never keep stale true.
    final r = await widget.apiService.getVaultEntry(widget.projectId, _entryId);
    if (!mounted) return;
    if (r['success'] == true && r['data'] is Map) {
      final fresh = Map<String, dynamic>.from(r['data'] as Map);
      setState(() {
        _entry = {
          ..._entry,
          ...fresh,
          if ((_entry['url']?.toString() ?? '').isNotEmpty && (fresh['url']?.toString() ?? '').isEmpty)
            'url': _entry['url'],
          if ((_entry['username']?.toString() ?? '').isNotEmpty &&
              (fresh['username']?.toString() ?? '').isEmpty)
            'username': _entry['username'],
        };
        _permissionsLoaded = true;
      });
    } else {
      setState(() => _permissionsLoaded = true);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (_revealedPassword != null) {
      widget.apiService.hideVaultPassword(widget.projectId, _entryId);
    }
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    AppToast.show(
      context,
      message: msg,
      type: error ? AppToastType.error : AppToastType.success,
    );
  }

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || _revealedPassword == null) return;
      _hidePassword();
    });
  }

  Future<void> _revealPassword() async {
    if (_revealedPassword != null) {
      await _hidePassword();
      return;
    }
    final r = await widget.apiService.revealVaultEntry(widget.projectId, _entryId);
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() {
        _revealedPassword = (r['data'] as Map? ?? {})['password']?.toString() ?? '';
      });
      _scheduleAutoHide();
    } else {
      _toast(r['error']?.toString() ?? 'Reveal failed', error: true);
    }
  }

  Future<void> _hidePassword() async {
    _hideTimer?.cancel();
    await widget.apiService.hideVaultPassword(widget.projectId, _entryId);
    if (mounted) setState(() => _revealedPassword = null);
  }

  Future<void> _copy(String field) async {
    final r = await widget.apiService.copyVaultField(widget.projectId, _entryId, field);
    if (!mounted) return;
    if (r['success'] == true) {
      await Clipboard.setData(ClipboardData(text: r['data']?['value']?.toString() ?? ''));
      _toast('Copied $field');
    } else {
      _toast(r['error']?.toString() ?? 'Copy failed', error: true);
    }
  }

  Future<void> _editEntry() async {
    if (!_canManageEntry) {
      _toast('You can view this entry but not edit it', error: true);
      return;
    }
    final e = _entry;
    final nameCtrl = TextEditingController(text: e['name']?.toString() ?? '');
    final urlCtrl = TextEditingController(text: e['url']?.toString() ?? '');
    final userCtrl = TextEditingController(text: e['username']?.toString() ?? '');
    final passCtrl = TextEditingController();
    final notesCtrl = TextEditingController(text: e['notes']?.toString() ?? '');

    InputDecoration deco(String label, IconData icon) => InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 13),
          prefixIcon: Icon(icon, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.85)),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.04),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.6)),
          ),
        );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Edit entry', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                  decoration: deco('Name', Icons.badge_outlined),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: urlCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                  decoration: deco('URL', Icons.language_outlined),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: userCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                  decoration: deco('Username', Icons.person_outline_rounded),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                  decoration: deco('Password (blank = keep)', Icons.lock_outline_rounded),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                  decoration: deco('Notes', Icons.notes_rounded),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim().isNotEmpty),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.featureVault),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final catId = e['category'] is int
        ? e['category'] as int
        : int.tryParse('${e['category']}');
    final r = await widget.apiService.updateVaultEntry(
      widget.projectId,
      _entryId,
      categoryId: catId,
      name: nameCtrl.text.trim(),
      url: urlCtrl.text.trim(),
      username: userCtrl.text.trim(),
      password: passCtrl.text.isEmpty ? null : passCtrl.text,
      notes: notesCtrl.text.trim(),
    );
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() {
        _entry = {
          ..._entry,
          'name': nameCtrl.text.trim(),
          'url': urlCtrl.text.trim(),
          'username': userCtrl.text.trim(),
          'notes': notesCtrl.text.trim(),
        };
      });
      widget.onChanged();
      if (!widget.embedded) Navigator.pop(context);
      _toast('Saved');
    } else {
      _toast(r['error']?.toString() ?? 'Save failed', error: true);
    }
  }

  Future<void> _deleteEntry() async {
    if (!_canManageEntry) {
      _toast('You can view this entry but not delete it', error: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete entry?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Remove "${_entry['name']}"?',
          style: const TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await widget.apiService.deleteVaultEntry(widget.projectId, _entryId);
    if (!mounted) return;
    if (r['success'] == true) {
      widget.onChanged();
      Navigator.pop(context);
    } else {
      _toast(r['error']?.toString() ?? 'Delete failed', error: true);
    }
  }

  Widget _formField({
    required String label,
    required IconData icon,
    required String value,
    VoidCallback? onCopy,
    VoidCallback? onOpen,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2, right: 10),
              child: Icon(icon, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.85)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: AppTheme.textMuted.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    value,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (onOpen != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Open',
                icon: const Icon(Icons.open_in_new_rounded, size: 18, color: AppTheme.textMuted),
                onPressed: onOpen,
              ),
            if (onCopy != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.textMuted),
                onPressed: onCopy,
              ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
      );

  @override
  Widget build(BuildContext context) {
    final name = _entry['name']?.toString() ?? 'Entry';
    final url = _entry['url']?.toString() ?? '';
    final user = _entry['username']?.toString() ?? '';
    final notes = _entry['notes']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          Row(
            children: [
              vaultIconBox(icon: vaultEntryIcon(_entry), color: AppTheme.featureVault),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          vaultSectionLabel('Details'),
          const SizedBox(height: 10),
        ],
        vaultSurfaceCard(
          child: Column(
            children: [
              if (url.isNotEmpty) ...[
                _formField(
                  label: 'URL',
                  icon: Icons.language_outlined,
                  value: url,
                  onCopy: () => _copy('url'),
                  onOpen: () {
                    final u = Uri.tryParse(url);
                    if (u != null) launchUrl(u, mode: LaunchMode.externalApplication);
                  },
                ),
                _divider(),
              ],
              if (user.isNotEmpty) ...[
                _formField(
                  label: 'Username',
                  icon: Icons.person_outline_rounded,
                  value: user,
                  onCopy: () => _copy('username'),
                ),
                _divider(),
              ],
              _formField(
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                value: _revealedPassword ?? '••••••••••••',
                onCopy: () => _copy('password'),
                trailing: TextButton(
                  onPressed: _revealPassword,
                  child: Text(
                    _revealedPassword != null ? 'Hide' : 'Show',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryBright,
                    ),
                  ),
                ),
              ),
              if (notes.isNotEmpty) ...[
                _divider(),
                _formField(
                  label: 'Notes',
                  icon: Icons.notes_rounded,
                  value: notes,
                ),
              ],
            ],
          ),
        ),
        if (_revealedPassword != null) ...[
          const SizedBox(height: 8),
          Text(
            'Password hides automatically in 10 seconds',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.7), fontSize: 11.5),
          ),
        ],
        if (_canManageEntry || _canShareEntry) ...[
          const SizedBox(height: 22),
          vaultSectionLabel('Actions'),
          const SizedBox(height: 10),
          vaultSurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                if (_canManageEntry) ...[
                  ListTile(
                    leading: vaultIconBox(
                      icon: Icons.edit_outlined,
                      color: AppTheme.primaryBright,
                      size: 40,
                      iconSize: 20,
                      radius: 12,
                    ),
                    title: const Text('Edit entry', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text('Update name, URL, username or password', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12)),
                    onTap: _editEntry,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  ListTile(
                    leading: vaultIconBox(
                      icon: Icons.delete_outline_rounded,
                      color: AppTheme.danger,
                      size: 40,
                      iconSize: 20,
                      radius: 12,
                    ),
                    title: const Text('Delete', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
                    subtitle: Text('Remove this credential permanently', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12)),
                    onTap: _deleteEntry,
                  ),
                ],
                if (_canShareEntry) ...[
                  if (_canManageEntry)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                    ),
                  ListTile(
                    leading: vaultIconBox(
                      icon: Icons.share_outlined,
                      color: AppTheme.accent,
                      size: 40,
                      iconSize: 20,
                      radius: 12,
                    ),
                    title: const Text('Share', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text('Grant access to teammates', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12)),
                    onTap: () {
                      showVaultShareSheet(
                        context: context,
                        apiService: widget.apiService,
                        projectId: widget.projectId,
                        entryId: _entryId,
                        entryName: name,
                        onChanged: widget.onChanged,
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
