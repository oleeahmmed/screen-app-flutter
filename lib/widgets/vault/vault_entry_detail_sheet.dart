import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
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
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface2,
    barrierColor: AppTheme.modalBarrierColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _VaultEntryDetailSheet(
      apiService: apiService,
      projectId: projectId,
      entry: entry,
      isAdmin: isAdmin,
      canEdit: canEdit,
      onChanged: onChanged,
    ),
  );
}

class _VaultEntryDetailSheet extends StatefulWidget {
  final ApiService apiService;
  final int projectId;
  final Map<String, dynamic> entry;
  final bool isAdmin;
  final bool canEdit;
  final VoidCallback onChanged;

  const _VaultEntryDetailSheet({
    required this.apiService,
    required this.projectId,
    required this.entry,
    required this.isAdmin,
    required this.canEdit,
    required this.onChanged,
  });

  @override
  State<_VaultEntryDetailSheet> createState() => _VaultEntryDetailSheetState();
}

class _VaultEntryDetailSheetState extends State<_VaultEntryDetailSheet> {
  String? _revealedPassword;
  Timer? _hideTimer;

  int get _entryId => widget.entry['id'] as int;

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
    final e = widget.entry;
    final nameCtrl = TextEditingController(text: e['name']?.toString() ?? '');
    final urlCtrl = TextEditingController(text: e['url']?.toString() ?? '');
    final userCtrl = TextEditingController(text: e['username']?.toString() ?? '');
    final passCtrl = TextEditingController();
    final notesCtrl = TextEditingController(text: e['notes']?.toString() ?? '');

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9)),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: const Text('Edit entry', style: TextStyle(color: AppTheme.textPrimary)),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: deco('Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: urlCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: deco('URL'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: userCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: deco('Username'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: deco('Password (blank = keep)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: deco('Notes'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim().isNotEmpty),
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
      widget.onChanged();
      Navigator.pop(context);
      _toast('Saved');
    } else {
      _toast(r['error']?.toString() ?? 'Save failed', error: true);
    }
  }

  Future<void> _deleteEntry() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: const Text('Delete entry?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Remove "${widget.entry['name']}"?',
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

  Widget _fieldRow({
    required String label,
    required String value,
    VoidCallback? onCopy,
    VoidCallback? onOpen,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.8), fontSize: 11),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
          ),
          if (onOpen != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.open_in_new, size: 16, color: AppTheme.textMuted),
              onPressed: onOpen,
            ),
          if (onCopy != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy, size: 16, color: AppTheme.textMuted),
              onPressed: onCopy,
            ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final name = e['name']?.toString() ?? 'Entry';
    final url = e['url']?.toString() ?? '';
    final user = e['username']?.toString() ?? '';
    final notes = e['notes']?.toString() ?? '';
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(vaultEntryIcon(e), color: AppTheme.featureVault, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              if (widget.canEdit)
                IconButton(
                  tooltip: 'Edit',
                  onPressed: _editEntry,
                  icon: const Icon(Icons.edit_outlined, size: 20, color: AppTheme.textMuted),
                ),
              if (widget.isAdmin)
                IconButton(
                  tooltip: 'Share',
                  onPressed: () {
                    showVaultShareSheet(
                      context: context,
                      apiService: widget.apiService,
                      projectId: widget.projectId,
                      entryId: _entryId,
                      entryName: name,
                      onChanged: widget.onChanged,
                    );
                  },
                  icon: const Icon(Icons.share_outlined, size: 20, color: AppTheme.textMuted),
                ),
              if (widget.canEdit)
                IconButton(
                  tooltip: 'Delete',
                  onPressed: _deleteEntry,
                  icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.danger),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (url.isNotEmpty)
            _fieldRow(
              label: 'URL',
              value: url,
              onCopy: () => _copy('url'),
              onOpen: () {
                final u = Uri.tryParse(url);
                if (u != null) launchUrl(u, mode: LaunchMode.externalApplication);
              },
            ),
          if (user.isNotEmpty)
            _fieldRow(label: 'Username', value: user, onCopy: () => _copy('username')),
          _fieldRow(
            label: 'Password',
            value: _revealedPassword ?? '••••••••',
            onCopy: () => _copy('password'),
            trailing: TextButton(
              onPressed: _revealPassword,
              child: Text(
                _revealedPassword != null ? 'Hide' : 'Show',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (notes.isNotEmpty)
            _fieldRow(label: 'Notes', value: notes),
          if (_revealedPassword != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Password hides automatically in 10 seconds',
                style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.7), fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
