import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'vault/vault_sheets.dart';

/// Project credentials vault — `/api/projects/{id}/vault/`.
class ProjectVaultTab extends StatefulWidget {
  final ApiService apiService;
  final int projectId;

  const ProjectVaultTab({
    super.key,
    required this.apiService,
    required this.projectId,
  });

  @override
  State<ProjectVaultTab> createState() => _ProjectVaultTabState();
}

class _ProjectVaultTabState extends State<ProjectVaultTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _entries = [];
  int? _selectedCategoryId;
  bool _favoritesOnly = false;
  final _searchCtrl = TextEditingController();
  final Map<int, String> _revealedPasswords = {};

  List<Map<String, dynamic>> get _visibleEntries {
    if (!_favoritesOnly) return _entries;
    return _entries.where((e) => e['is_favorite'] == true).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final catR = await widget.apiService.getVaultCategories(widget.projectId);
    final entR = await widget.apiService.getVaultEntries(
      widget.projectId,
      categoryId: _selectedCategoryId,
      query: _searchCtrl.text.trim(),
    );
    if (!mounted) return;
    if (catR['success'] != true) {
      setState(() {
        _loading = false;
        _error = catR['error']?.toString() ?? 'Failed to load vault';
      });
      return;
    }
    setState(() {
      _categories = (catR['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _entries = entR['success'] == true
          ? (entR['data'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : [];
      _loading = false;
      _error = entR['success'] == true ? null : entR['error']?.toString();
    });
  }

  Future<void> _showCategoryDialog({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final descCtrl = TextEditingController(text: existing?['description']?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: Text(
          isEdit ? 'Edit category' : 'New category',
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogField('Name', nameCtrl),
            const SizedBox(height: 10),
            _dialogField('Description (optional)', descCtrl, maxLines: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim().isNotEmpty),
            child: Text(isEdit ? 'Save' : 'Create'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;

    final Map<String, dynamic> r;
    if (isEdit) {
      r = await widget.apiService.updateVaultCategory(
        widget.projectId,
        existing!['id'] as int,
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
      );
    } else {
      r = await widget.apiService.createVaultCategory(
        widget.projectId,
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
      );
    }
    if (!mounted) return;
    if (r['success'] == true) {
      await _loadAll();
    } else {
      _snack(r['error']?.toString() ?? 'Failed', AppTheme.danger);
    }
  }

  Future<void> _deleteCategory(Map<String, dynamic> cat) async {
    final id = cat['id'] as int;
    final count = cat['entry_count'] ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: const Text('Delete category?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          count > 0
              ? '"${cat['name']}" has $count credential(s). Delete anyway?'
              : 'Remove "${cat['name']}"?',
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
    final r = await widget.apiService.deleteVaultCategory(widget.projectId, id);
    if (!mounted) return;
    if (r['success'] == true) {
      if (_selectedCategoryId == id) _selectedCategoryId = null;
      await _loadAll();
    } else {
      _snack(r['error']?.toString() ?? 'Delete failed', AppTheme.danger);
    }
  }

  Future<void> _showEntryDialog({Map<String, dynamic>? existing}) async {
    if (_categories.isEmpty) {
      _snack('Create a category first', AppTheme.warning);
      return;
    }
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final urlCtrl = TextEditingController(text: existing?['url']?.toString() ?? '');
    final userCtrl = TextEditingController(text: existing?['username']?.toString() ?? '');
    final passCtrl = TextEditingController();
    final notesCtrl = TextEditingController(text: existing?['notes']?.toString() ?? '');
    var catId = existing?['category'] is int
        ? existing!['category'] as int
        : int.tryParse('${existing?['category']}') ?? _categories.first['id'] as int;
    var favorite = existing?['is_favorite'] == true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppTheme.surface2,
          insetPadding: AppTheme.dialogInsets(context),
          title: Text(
            isEdit ? 'Edit credential' : 'Add credential',
            style: const TextStyle(color: AppTheme.textPrimary),
          ),
          content: SizedBox(
            width: AppTheme.dialogMaxWidth(context, max: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: catId,
                    dropdownColor: AppTheme.surface2,
                    decoration: _inputDeco('Category'),
                    items: _categories.map((c) {
                      final id = c['id'] as int;
                      return DropdownMenuItem(value: id, child: Text(c['name']?.toString() ?? 'Category'));
                    }).toList(),
                    onChanged: (v) => setDlg(() => catId = v ?? catId),
                  ),
                  const SizedBox(height: 10),
                  _dialogField('Name', nameCtrl),
                  const SizedBox(height: 10),
                  _dialogField('URL', urlCtrl),
                  const SizedBox(height: 10),
                  _dialogField('Username', userCtrl),
                  const SizedBox(height: 10),
                  _dialogField(isEdit ? 'Password (leave blank to keep)' : 'Password', passCtrl, obscure: true),
                  const SizedBox(height: 10),
                  _dialogField('Notes', notesCtrl, maxLines: 3),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Favorite', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    value: favorite,
                    onChanged: (v) => setDlg(() => favorite = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim().isNotEmpty), child: Text(isEdit ? 'Save' : 'Add')),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;

    final Map<String, dynamic> r;
    if (isEdit) {
      r = await widget.apiService.updateVaultEntry(
        widget.projectId,
        existing!['id'] as int,
        categoryId: catId,
        name: nameCtrl.text.trim(),
        url: urlCtrl.text.trim(),
        username: userCtrl.text.trim(),
        password: passCtrl.text.isEmpty ? null : passCtrl.text,
        notes: notesCtrl.text.trim(),
        isFavorite: favorite,
      );
    } else {
      r = await widget.apiService.createVaultEntry(
        widget.projectId,
        categoryId: catId,
        name: nameCtrl.text.trim(),
        url: urlCtrl.text.trim(),
        username: userCtrl.text.trim(),
        password: passCtrl.text,
        notes: notesCtrl.text.trim(),
        isFavorite: favorite,
      );
    }
    if (!mounted) return;
    if (r['success'] == true) {
      await _loadAll();
      _snack(isEdit ? 'Credential updated' : 'Credential added', AppTheme.success);
    } else {
      _snack(r['error']?.toString() ?? 'Save failed', AppTheme.danger);
    }
  }

  Future<void> _revealPassword(int entryId) async {
    if (_revealedPasswords.containsKey(entryId)) {
      await widget.apiService.hideVaultPassword(widget.projectId, entryId);
      if (!mounted) return;
      setState(() => _revealedPasswords.remove(entryId));
      return;
    }
    final r = await widget.apiService.revealVaultEntry(widget.projectId, entryId);
    if (!mounted) return;
    if (r['success'] == true) {
      final data = r['data'] as Map? ?? {};
      final pwd = data['password']?.toString() ?? '';
      setState(() => _revealedPasswords[entryId] = pwd);
      // Refresh url/username from reveal response if present
      final idx = _entries.indexWhere((e) => e['id'] == entryId);
      if (idx >= 0 && data.isNotEmpty) {
        setState(() {
          if (data['url'] != null) _entries[idx]['url'] = data['url'];
          if (data['username'] != null) _entries[idx]['username'] = data['username'];
        });
      }
    } else {
      _snack(r['error']?.toString() ?? 'Reveal failed', AppTheme.danger);
    }
  }

  Future<void> _toggleFavorite(Map<String, dynamic> entry) async {
    final id = entry['id'] as int;
    final next = entry['is_favorite'] != true;
    final r = await widget.apiService.updateVaultEntry(
      widget.projectId,
      id,
      isFavorite: next,
    );
    if (!mounted) return;
    if (r['success'] == true) {
      await _loadAll();
    } else {
      _snack(r['error']?.toString() ?? 'Update failed', AppTheme.danger);
    }
  }

  Future<void> _copyField(int entryId, String field) async {
    final r = await widget.apiService.copyVaultField(widget.projectId, entryId, field);
    if (!mounted) return;
    if (r['success'] == true) {
      final value = r['data']?['value']?.toString() ?? '';
      await Clipboard.setData(ClipboardData(text: value));
      _snack('Copied $field', AppTheme.success);
    } else {
      _snack(r['error']?.toString() ?? 'Copy failed', AppTheme.danger);
    }
  }

  Future<void> _uploadAttachment(Map<String, dynamic> entry) async {
    final id = entry['id'] as int;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _snack('Could not read file', AppTheme.danger);
      return;
    }
    final r = await widget.apiService.uploadVaultAttachment(
      widget.projectId,
      id,
      bytes,
      file.name,
      title: file.name,
    );
    if (!mounted) return;
    if (r['success'] == true) {
      await _loadAll();
      _snack('Attachment uploaded', AppTheme.success);
    } else {
      _snack(r['error']?.toString() ?? 'Upload failed', AppTheme.danger);
    }
  }

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    final id = entry['id'] as int;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: const Text('Delete credential?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Remove "${entry['name']}" from vault?', style: const TextStyle(color: AppTheme.textMuted)),
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
    final r = await widget.apiService.deleteVaultEntry(widget.projectId, id);
    if (!mounted) return;
    if (r['success'] == true) {
      _revealedPasswords.remove(id);
      await _loadAll();
    } else {
      _snack(r['error']?.toString() ?? 'Delete failed', AppTheme.danger);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  InputDecoration _inputDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
    );
  }

  Widget _dialogField(String label, TextEditingController c, {int maxLines = 1, bool obscure = false}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      obscureText: obscure,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: _inputDeco(label),
    );
  }

  void _showCategoryMenu(Map<String, dynamic> cat) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface2,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppTheme.textMuted),
              title: Text('Edit "${cat['name']}"', style: const TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _showCategoryDialog(existing: cat);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: const Text('Delete category', style: TextStyle(color: AppTheme.danger)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteCategory(cat);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryBright));
    }
    final visible = _visibleEntries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  decoration: _inputDeco('Search vault').copyWith(
                    prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted, size: 20),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _loadAll(),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Vault activity',
                onPressed: () => showVaultActivitySheet(
                  context: context,
                  apiService: widget.apiService,
                  projectId: widget.projectId,
                ),
                icon: const Icon(Icons.history_rounded, color: AppTheme.textMuted),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.textMuted),
              ),
              IconButton(
                tooltip: 'New category',
                onPressed: () => _showCategoryDialog(),
                icon: const Icon(Icons.create_new_folder_outlined, color: AppTheme.primaryBright),
              ),
              FilledButton.icon(
                onPressed: () => _showEntryDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 12)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: const Text('All'),
                  selected: _selectedCategoryId == null && !_favoritesOnly,
                  onSelected: (_) {
                    setState(() {
                      _selectedCategoryId = null;
                      _favoritesOnly = false;
                    });
                    _loadAll();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  avatar: const Icon(Icons.star_rounded, size: 16),
                  label: const Text('Favorites'),
                  selected: _favoritesOnly,
                  onSelected: (_) {
                    setState(() {
                      _favoritesOnly = true;
                      _selectedCategoryId = null;
                    });
                    _loadAll();
                  },
                ),
              ),
              ..._categories.map((c) {
                final id = c['id'] as int;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onLongPress: () => _showCategoryMenu(c),
                    child: FilterChip(
                      label: Text('${c['name']} (${c['entry_count'] ?? 0})'),
                      selected: _selectedCategoryId == id && !_favoritesOnly,
                      onSelected: (_) {
                        setState(() {
                          _selectedCategoryId = id;
                          _favoritesOnly = false;
                        });
                        _loadAll();
                      },
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
          ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 48, color: Colors.white.withValues(alpha: 0.15)),
                      const SizedBox(height: 8),
                      Text(
                        _categories.isEmpty ? 'No categories yet' : 'No credentials in this view',
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: visible.length,
                  itemBuilder: (ctx, i) => _entryCard(visible[i]),
                ),
        ),
      ],
    );
  }

  Widget _entryCard(Map<String, dynamic> e) {
    final id = e['id'] as int;
    final revealed = _revealedPasswords[id];
    final url = e['url']?.toString() ?? '';
    final username = e['username']?.toString() ?? '';
    final attachments = (e['attachments'] as List? ?? []).whereType<Map>().toList();
    final shares = (e['shares'] as List? ?? []).whereType<Map>().toList();
    final name = e['name']?.toString() ?? 'Credential';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.glassPanel(borderRadius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  e['is_favorite'] == true ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: e['is_favorite'] == true ? AppTheme.warning : AppTheme.textMuted,
                  size: 18,
                ),
                onPressed: () => _toggleFavorite(e),
              ),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              if (shares.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: '${shares.length} share(s)',
                    child: Icon(Icons.people_outline, size: 16, color: AppTheme.textMuted.withValues(alpha: 0.7)),
                  ),
                ),
              Text(
                e['category_name']?.toString() ?? '',
                style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.8), fontSize: 10),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppTheme.textMuted, size: 18),
                color: AppTheme.surface2,
                onSelected: (v) {
                  if (v == 'edit') _showEntryDialog(existing: e);
                  if (v == 'share') {
                    showVaultShareSheet(
                      context: context,
                      apiService: widget.apiService,
                      projectId: widget.projectId,
                      entryId: id,
                      entryName: name,
                      onChanged: _loadAll,
                    );
                  }
                  if (v == 'attach') _uploadAttachment(e);
                  if (v == 'activity') {
                    showVaultActivitySheet(
                      context: context,
                      apiService: widget.apiService,
                      projectId: widget.projectId,
                      entryId: id,
                      entryName: name,
                    );
                  }
                  if (v == 'delete') _deleteEntry(e);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'share', child: Text('Share')),
                  PopupMenuItem(value: 'attach', child: Text('Add attachment')),
                  PopupMenuItem(value: 'activity', child: Text('Activity')),
                  PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppTheme.danger))),
                ],
              ),
            ],
          ),
          if (url.isNotEmpty) ...[
            const SizedBox(height: 8),
            _fieldRow('URL', url, onCopy: () => _copyField(id, 'url'), onOpen: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
          ],
          if (username.isNotEmpty) ...[
            const SizedBox(height: 6),
            _fieldRow('User', username, onCopy: () => _copyField(id, 'username')),
          ],
          const SizedBox(height: 6),
          _fieldRow(
            'Password',
            revealed ?? '••••••••',
            onCopy: revealed != null ? () => Clipboard.setData(ClipboardData(text: revealed)) : () => _copyField(id, 'password'),
            trailing: TextButton(
              onPressed: () => _revealPassword(id),
              child: Text(revealed != null ? 'Hide' : 'Reveal', style: const TextStyle(fontSize: 11)),
            ),
          ),
          if ((e['notes']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(e['notes'].toString(), style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 11)),
          ],
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: attachments.map((a) {
                final title = a['title']?.toString() ?? a['file']?.toString() ?? 'File';
                final fileUrl = a['file_url']?.toString();
                return ActionChip(
                  label: Text(title, style: const TextStyle(fontSize: 10)),
                  avatar: const Icon(Icons.attach_file, size: 14),
                  onPressed: fileUrl != null && fileUrl.isNotEmpty
                      ? () => launchUrl(Uri.parse(fileUrl), mode: LaunchMode.externalApplication)
                      : null,
                );
              }).toList(),
            ),
          ],
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _uploadAttachment(e),
                icon: const Icon(Icons.attach_file, size: 14),
                label: const Text('Attach', style: TextStyle(fontSize: 11)),
              ),
              if (e['updated_at'] != null)
                Expanded(
                  child: Text(
                    'Updated ${_fmt(e['updated_at'])}',
                    textAlign: TextAlign.end,
                    style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.55), fontSize: 10),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(String label, String value, {VoidCallback? onCopy, VoidCallback? onOpen, Widget? trailing}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 64, child: Text(label, style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.75), fontSize: 11))),
        Expanded(child: SelectableText(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12))),
        if (onOpen != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.open_in_new, size: 16, color: AppTheme.textMuted),
            onPressed: onOpen,
          ),
        if (onCopy != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 16, color: AppTheme.textMuted),
            onPressed: onCopy,
          ),
        if (trailing != null) trailing,
      ],
    );
  }

  String _fmt(dynamic iso) {
    try {
      return DateFormat('dd MMM HH:mm').format(DateTime.parse(iso.toString()).toLocal());
    } catch (_) {
      return '';
    }
  }
}
