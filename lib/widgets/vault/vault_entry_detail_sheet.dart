import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/user_data_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_toast.dart';
import '../../utils/local_file_actions.dart';
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
  int? _busyAttachmentId;

  int get _entryId => _entry['id'] as int;

  List<Map<String, dynamic>> get _attachments {
    final raw = _entry['attachments'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  bool get _canManageEntry =>
      _permissionsLoaded &&
      vaultEntryCanEdit(
        _entry,
        isVaultAdmin: widget.isAdmin,
        currentUserId: _currentUserId ?? widget.currentUserId,
      );

  bool get _canEditNotesFiles =>
      _permissionsLoaded &&
      vaultEntryCanEditNotesAttachments(
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

  Future<void> _editEntry({bool notesAndFilesOnly = false}) async {
    final secretsOk = _canManageEntry;
    final notesOk = _canEditNotesFiles;
    if (!secretsOk && !notesOk) {
      _toast('You can view this entry but not edit it', error: true);
      return;
    }
    final limited = notesAndFilesOnly || !secretsOk;
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

    final pendingFiles = <Map<String, dynamic>>[];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          limited ? 'Edit notes & files' : 'Edit entry',
          style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!limited) ...[
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
                ],
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                  decoration: deco('Notes', Icons.notes_rounded),
                ),
                const SizedBox(height: 12),
                vaultPendingFilesPicker(
                  pendingFiles: pendingFiles,
                  onAdd: () async {
                    final picked = await pickVaultPendingFiles(
                      ctx,
                      alreadyCount: _attachments.length + pendingFiles.length,
                    );
                    if (picked.isEmpty) return;
                    pendingFiles.addAll(picked);
                    setD(() {});
                  },
                  onRemove: (i) => setD(() => pendingFiles.removeAt(i)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (limited) {
                Navigator.pop(ctx, true);
              } else {
                Navigator.pop(ctx, nameCtrl.text.trim().isNotEmpty);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.featureVault),
            child: const Text('Save'),
          ),
        ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final catId = e['category'] is int
        ? e['category'] as int
        : int.tryParse('${e['category']}');
    final r = limited
        ? await widget.apiService.updateVaultEntry(
            widget.projectId,
            _entryId,
            notes: notesCtrl.text.trim(),
            files: pendingFiles,
          )
        : await widget.apiService.updateVaultEntry(
            widget.projectId,
            _entryId,
            categoryId: catId,
            name: nameCtrl.text.trim(),
            url: urlCtrl.text.trim(),
            username: userCtrl.text.trim(),
            password: passCtrl.text.isEmpty ? null : passCtrl.text,
            notes: notesCtrl.text.trim(),
            files: pendingFiles,
          );
    if (!mounted) return;
    if (r['success'] == true) {
      final data = r['data'];
      setState(() {
        if (data is Map) {
          _entry = {..._entry, ...Map<String, dynamic>.from(data)};
        } else if (limited) {
          _entry = {..._entry, 'notes': notesCtrl.text.trim()};
        } else {
          _entry = {
            ..._entry,
            'name': nameCtrl.text.trim(),
            'url': urlCtrl.text.trim(),
            'username': userCtrl.text.trim(),
            'notes': notesCtrl.text.trim(),
          };
        }
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

  String _attachmentName(Map<String, dynamic> a) {
    final title = a['title']?.toString().trim() ?? '';
    if (title.isNotEmpty) return title;
    final original = a['original_filename']?.toString().trim() ?? '';
    if (original.isNotEmpty) return original;
    return 'File';
  }

  String _attachmentSizeLabel(Map<String, dynamic> a) {
    final raw = a['file_size'];
    final bytes = raw is int ? raw : int.tryParse('$raw') ?? 0;
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _attachmentIcon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if ({'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(ext)) return Icons.image_outlined;
    if ({'pdf'}.contains(ext)) return Icons.picture_as_pdf_outlined;
    if ({'xls', 'xlsx', 'csv'}.contains(ext)) return Icons.table_chart_outlined;
    if ({'doc', 'docx', 'rtf', 'odt'}.contains(ext)) return Icons.description_outlined;
    if ({'env', 'ini', 'conf', 'cfg', 'yml', 'yaml', 'json', 'xml'}.contains(ext)) {
      return Icons.settings_outlined;
    }
    return Icons.attach_file_rounded;
  }

  Future<void> _openAttachment(Map<String, dynamic> a) async {
    final id = a['id'] is int ? a['id'] as int : int.tryParse('${a['id']}');
    if (id == null || _busyAttachmentId != null) return;
    setState(() => _busyAttachmentId = id);
    final r = await widget.apiService.downloadVaultAttachment(widget.projectId, _entryId, id);
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() => _busyAttachmentId = null);
      _toast(r['error']?.toString() ?? 'Download failed', error: true);
      return;
    }
    try {
      final filename = (r['filename']?.toString().trim().isNotEmpty == true)
          ? r['filename'].toString()
          : _attachmentName(a);
      final safe = filename.replaceAll(RegExp(r'[^\w.\- ()]'), '_');
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/vault_${_entryId}_${id}_$safe';
      final file = File(path);
      await file.writeAsBytes(List<int>.from(r['bytes'] as List<int>), flush: true);
      final opened = await LocalFileActions.openFile(path);
      if (mounted && opened != 'ok' && opened != 'no_handler') {
        _toast(opened == 'missing' ? 'Could not open file' : opened, error: true);
      }
    } catch (e) {
      if (mounted) _toast('$e', error: true);
    }
    if (mounted) setState(() => _busyAttachmentId = null);
  }

  Future<void> _deleteAttachment(Map<String, dynamic> a) async {
    if (!_canEditNotesFiles) return;
    final id = a['id'] is int ? a['id'] as int : int.tryParse('${a['id']}');
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: const Text('Remove file?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Delete "${_attachmentName(a)}"?',
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
    final r = await widget.apiService.deleteVaultAttachment(widget.projectId, _entryId, id);
    if (!mounted) return;
    if (r['success'] != true) {
      _toast(r['error']?.toString() ?? 'Delete failed', error: true);
      return;
    }
    widget.onChanged();
    setState(() {
      final next = List<Map<String, dynamic>>.from(_attachments)..removeWhere((e) => e['id'] == id);
      _entry = {..._entry, 'attachments': next};
    });
    _toast('File removed');
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
        if (_attachments.isNotEmpty || _canEditNotesFiles) ...[
          const SizedBox(height: 22),
          vaultSectionLabel('Files'),
          const SizedBox(height: 10),
          vaultSurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                if (_attachments.isEmpty && _canEditNotesFiles)
                  ListTile(
                    leading: vaultIconBox(
                      icon: Icons.upload_file_outlined,
                      color: AppTheme.featureVault,
                      size: 40,
                      iconSize: 20,
                      radius: 12,
                    ),
                    title: const Text('No files yet', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text('Tap to add attachments', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12)),
                    onTap: () => _editEntry(notesAndFilesOnly: !_canManageEntry),
                  ),
                ..._attachments.map((a) {
                  final name = _attachmentName(a);
                  final size = _attachmentSizeLabel(a);
                  final id = a['id'] is int ? a['id'] as int : int.tryParse('${a['id']}');
                  final busy = id != null && id == _busyAttachmentId;
                  return ListTile(
                    leading: vaultIconBox(
                      icon: _attachmentIcon(name),
                      color: AppTheme.featureVault,
                      size: 40,
                      iconSize: 20,
                      radius: 12,
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    subtitle: size.isEmpty
                        ? null
                        : Text(size, style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12)),
                    onTap: busy ? null : () => _openAttachment(a),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (busy)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.featureVault),
                          )
                        else
                          IconButton(
                            tooltip: 'Open',
                            icon: const Icon(Icons.download_outlined, color: AppTheme.textMuted, size: 20),
                            onPressed: () => _openAttachment(a),
                          ),
                        if (_canEditNotesFiles)
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                            onPressed: () => _deleteAttachment(a),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
        if (_canManageEntry || _canEditNotesFiles || _canShareEntry) ...[
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
                    subtitle: Text('Update name, files, URL, username or password', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12)),
                    onTap: () => _editEntry(),
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
                ] else if (_canEditNotesFiles) ...[
                  ListTile(
                    leading: vaultIconBox(
                      icon: Icons.note_alt_outlined,
                      color: AppTheme.primaryBright,
                      size: 40,
                      iconSize: 20,
                      radius: 12,
                    ),
                    title: const Text('Edit notes & files', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text('Update notes and upload attachments', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12)),
                    onTap: () => _editEntry(notesAndFilesOnly: true),
                  ),
                ],
                if (_canShareEntry) ...[
                  if (_canManageEntry || _canEditNotesFiles)
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
