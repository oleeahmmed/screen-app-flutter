import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/user_data_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import 'vault/vault_category_access_sheet.dart';
import 'vault/vault_entry_detail_sheet.dart';
import 'vault/vault_helpers.dart';

/// Project vault — same screen for admin & user; actions differ by role.
class ProjectVaultTab extends StatefulWidget {
  final ApiService apiService;
  final int projectId;
  /// When set, open directly on this category (from hub category tap).
  final int? initialCategoryId;
  /// Hide category strip / admin chrome when opened from a single category.
  final bool lockToCategory;

  const ProjectVaultTab({
    super.key,
    required this.apiService,
    required this.projectId,
    this.initialCategoryId,
    this.lockToCategory = false,
  });

  @override
  State<ProjectVaultTab> createState() => _ProjectVaultTabState();
}

class _ProjectVaultTabState extends State<ProjectVaultTab> {
  bool _loading = true;
  String? _error;
  bool _isAdmin = false;
  int? _currentUserId;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _entries = [];
  int? _categoryId;

  Map<String, dynamic>? get _selectedCat {
    if (_categoryId == null) return null;
    for (final c in _categories) {
      if (c['id'] == _categoryId) return c;
    }
    return null;
  }

  bool _canEditCat(Map<String, dynamic>? c) =>
      vaultCanEditCategory(c, isAdmin: _isAdmin);

  @override
  void initState() {
    super.initState();
    _loadUser();
    _load();
  }

  Future<void> _loadUser() async {
    final id = int.tryParse(await UserDataService.getUserId());
    if (mounted) setState(() => _currentUserId = id);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final catR = await widget.apiService.getVaultCategories(widget.projectId);
    final projR = await widget.apiService.getProjectDetail(widget.projectId);
    final companyPrivileged = await UserDataService.isManagerOrAbove();
    if (!mounted) return;

    if (catR['success'] != true) {
      setState(() {
        _loading = false;
        _error = catR['error']?.toString() ?? 'Failed to load vault';
      });
      return;
    }

    final cats = (catR['data'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final project = projR['success'] == true && projR['data'] is Map
        ? Map<String, dynamic>.from(projR['data'] as Map)
        : <String, dynamic>{};
    final admin = companyPrivileged ||
        cats.any((c) => c['can_admin'] == true) ||
        project['is_manager'] == true;

    int? selected = widget.initialCategoryId ?? _categoryId;
    if (selected != null && !cats.any((c) => c['id'] == selected)) {
      selected = null;
    }
    selected ??= cats.isNotEmpty ? cats.first['id'] as int : null;

    List<Map<String, dynamic>> entries = [];
    String? entryErr;
    if (selected != null) {
      final entR = await widget.apiService.getVaultEntries(
        widget.projectId,
        categoryId: selected,
      );
      if (!mounted) return;
      if (entR['success'] == true) {
        entries = (entR['data'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
        entryErr = entR['error']?.toString();
      }
    }

    setState(() {
      _categories = cats;
      _isAdmin = admin;
      _categoryId = selected;
      _entries = entries;
      _loading = false;
      _error = entryErr;
    });
  }

  Future<void> _selectCategory(int id) async {
    if (_categoryId == id) return;
    setState(() {
      _categoryId = id;
      _entries = [];
      _error = null;
    });
    final entR = await widget.apiService.getVaultEntries(
      widget.projectId,
      categoryId: id,
    );
    if (!mounted) return;
    setState(() {
      _entries = entR['success'] == true
          ? (entR['data'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : [];
      if (entR['success'] != true) {
        _error = entR['error']?.toString();
      }
    });
  }

  void _toast(String msg, {bool error = false}) {
    AppToast.show(
      context,
      message: msg,
      type: error ? AppToastType.error : AppToastType.success,
    );
  }

  InputDecoration _deco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Future<void> _editCategory({Map<String, dynamic>? existing}) async {
    if (!_isAdmin) return;
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: Text(
          existing == null ? 'New category' : 'Rename category',
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: _deco('Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim().isNotEmpty),
            child: Text(existing == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    final Map<String, dynamic> r;
    if (existing != null) {
      r = await widget.apiService.updateVaultCategory(
        widget.projectId,
        existing['id'] as int,
        name: name,
      );
    } else {
      r = await widget.apiService.createVaultCategory(widget.projectId, name: name);
    }
    if (!mounted) return;
    if (r['success'] == true) {
      await _load();
      _toast(existing == null ? 'Category created' : 'Saved');
    } else {
      _toast(r['error']?.toString() ?? 'Failed', error: true);
    }
  }

  Future<void> _deleteCategory(Map<String, dynamic> cat) async {
    if (!_isAdmin) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface2,
        title: const Text('Delete category?', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Remove "${cat['name']}"?',
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
    final r = await widget.apiService.deleteVaultCategory(widget.projectId, cat['id'] as int);
    if (!mounted) return;
    if (r['success'] == true) {
      _categoryId = null;
      await _load();
    } else {
      _toast(r['error']?.toString() ?? 'Delete failed', error: true);
    }
  }

  void _openPeople(Map<String, dynamic> cat) {
    if (!_isAdmin) return;
    showVaultCategoryAccessSheet(
      context: context,
      apiService: widget.apiService,
      projectId: widget.projectId,
      categoryId: cat['id'] as int,
      categoryName: cat['name']?.toString() ?? 'Category',
      onChanged: _load,
    );
  }

  Future<void> _editEntry({Map<String, dynamic>? existing}) async {
    final cat = _selectedCat;
    if (!_canEditCat(cat)) {
      _toast(
        _categories.isEmpty
            ? (_isAdmin ? 'Create a category first' : 'No access yet — ask admin')
            : 'No edit permission on this category',
        error: true,
      );
      return;
    }
    final catId = cat!['id'] as int;
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final urlCtrl = TextEditingController(text: existing?['url']?.toString() ?? '');
    final userCtrl = TextEditingController(text: existing?['username']?.toString() ?? '');
    final passCtrl = TextEditingController();
    final notesCtrl = TextEditingController(text: existing?['notes']?.toString() ?? '');
    final pendingFiles = <Map<String, dynamic>>[];
    final isNew = existing == null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.surface2,
          title: Text(
            isNew ? 'New entry' : 'Edit entry',
            style: const TextStyle(color: AppTheme.textPrimary),
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(controller: nameCtrl, style: const TextStyle(color: AppTheme.textPrimary), decoration: _deco('Name *')),
                  const SizedBox(height: 10),
                  TextField(controller: urlCtrl, style: const TextStyle(color: AppTheme.textPrimary), decoration: _deco('URL')),
                  const SizedBox(height: 10),
                  TextField(controller: userCtrl, style: const TextStyle(color: AppTheme.textPrimary), decoration: _deco('Username')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: _deco(isNew ? 'Password' : 'Password (blank = keep)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: _deco('Notes'),
                  ),
                  const SizedBox(height: 12),
                  vaultPendingFilesPicker(
                    pendingFiles: pendingFiles,
                    onAdd: () async {
                      final existingCount = existing == null
                          ? 0
                          : (existing['attachments'] is List ? (existing['attachments'] as List).length : 0);
                      final picked = await pickVaultPendingFiles(
                        ctx,
                        alreadyCount: existingCount + pendingFiles.length,
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
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim().isNotEmpty),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.featureVault),
              child: Text(isNew ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final Map<String, dynamic> r;
    if (existing != null) {
      r = await widget.apiService.updateVaultEntry(
        widget.projectId,
        existing['id'] as int,
        categoryId: catId,
        name: nameCtrl.text.trim(),
        url: urlCtrl.text.trim(),
        username: userCtrl.text.trim(),
        password: passCtrl.text.isEmpty ? null : passCtrl.text,
        notes: notesCtrl.text.trim(),
        files: pendingFiles,
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
        files: pendingFiles,
      );
    }
    if (!mounted) return;
    if (r['success'] == true) {
      await _selectCategory(catId);
      _toast(existing == null ? 'Entry added' : 'Saved');
    } else {
      _toast(r['error']?.toString() ?? 'Failed', error: true);
    }
  }

  void _openEntryDetail(Map<String, dynamic> e) {
    showVaultEntryDetailSheet(
      context: context,
      apiService: widget.apiService,
      projectId: widget.projectId,
      entry: e,
      isAdmin: _isAdmin,
      canEdit: vaultEntryCanEdit(
        e,
        isVaultAdmin: _isAdmin,
        currentUserId: _currentUserId,
      ),
      currentUserId: _currentUserId,
      onChanged: () {
        if (_categoryId != null) _selectCategory(_categoryId!);
      },
    );
  }

  void _categoryMenu(Map<String, dynamic> c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.people_outline, color: AppTheme.featureVault),
              title: const Text('People', style: TextStyle(color: AppTheme.textPrimary)),
              subtitle: const Text(
                'Grant category access',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _openPeople(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppTheme.textMuted),
              title: const Text('Rename', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _editCategory(existing: c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteCategory(c);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(Map<String, dynamic> c) {
    final id = c['id'] as int;
    final selected = id == _categoryId;
    final permLabel = _isAdmin ? '' : vaultCategoryPermissionLabel(c);
    final isEdit = permLabel == 'Can edit' || permLabel == 'Admin';

    return Material(
      color: selected
          ? AppTheme.featureVault.withValues(alpha: 0.28)
          : Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _selectCategory(id),
        onLongPress: _isAdmin ? () => _categoryMenu(c) : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.fromLTRB(14, 10, _isAdmin ? 6 : 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppTheme.featureVault.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${c['name']} (${c['entry_count'] ?? 0})',
                style: TextStyle(
                  color: selected ? Colors.white : AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
              if (permLabel.isNotEmpty) vaultPermissionChip(permLabel, edit: isEdit),
              if (_isAdmin)
                InkWell(
                  onTap: () => _categoryMenu(c),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.more_horiz, size: 16, color: AppTheme.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entryTile(Map<String, dynamic> e) {
    final name = e['name']?.toString() ?? 'Entry';
    final user = e['username']?.toString() ?? '';
    final url = e['url']?.toString() ?? '';
    final subtitle = user.isNotEmpty
        ? user
        : (url.isNotEmpty ? url : 'Tap to view credentials');

    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _openEntryDetail(e),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.featureVault.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(vaultEntryIcon(e), size: 18, color: AppTheme.featureVault),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryBright));
    }

    final canEdit = _canEditCat(_selectedCat);
    final cat = _selectedCat;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              vaultRoleBadge(isAdmin: _isAdmin),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isAdmin
                      ? 'Manage categories, access & credentials'
                      : 'Only categories shared with you',
                  style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9), fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 20, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
        if (!widget.lockToCategory)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                if (_isAdmin)
                  OutlinedButton.icon(
                    onPressed: () => _editCategory(),
                    icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                    label: const Text('Category'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
                    ),
                  ),
                if (_isAdmin && cat != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _openPeople(cat),
                    icon: const Icon(Icons.people_outline, size: 16),
                    label: const Text('People'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.featureVault,
                      side: BorderSide(color: AppTheme.featureVault.withValues(alpha: 0.45)),
                    ),
                  ),
                ],
                const Spacer(),
                if (canEdit)
                  FilledButton.icon(
                    onPressed: () => _editEntry(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Entry'),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.featureVault),
                  ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                if (_isAdmin && cat != null)
                  OutlinedButton.icon(
                    onPressed: () => _openPeople(cat),
                    icon: const Icon(Icons.people_outline, size: 16),
                    label: const Text('People'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.featureVault,
                      side: BorderSide(color: AppTheme.featureVault.withValues(alpha: 0.45)),
                    ),
                  ),
                const Spacer(),
                if (canEdit)
                  FilledButton.icon(
                    onPressed: () => _editEntry(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Entry'),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.featureVault),
                  ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
          ),
        if (!widget.lockToCategory)
          SizedBox(
            height: 44,
            child: _categories.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _isAdmin
                            ? 'No categories yet — tap Category to create one'
                            : 'No category access yet — ask your admin',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _categoryChip(_categories[i]),
                  ),
          ),
        if (cat != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Text(
                  cat['name']?.toString() ?? 'Category',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (!_isAdmin) ...[
                  const SizedBox(width: 8),
                  vaultPermissionChip(
                    vaultCategoryPermissionLabel(cat),
                    edit: vaultCategoryPermissionLabel(cat) == 'Can edit',
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 8),
        const Divider(height: 1, color: Color(0x22FFFFFF)),
        Expanded(
          child: _categoryId == null
              ? Center(
                  child: _isAdmin
                      ? FilledButton(
                          onPressed: () => _editCategory(),
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.featureVault),
                          child: const Text('Create first category'),
                        )
                      : const Text(
                          'Nothing to show yet',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                )
              : _entries.isEmpty
                  ? Center(
                      child: canEdit
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'No entries in this category',
                                  style: TextStyle(color: AppTheme.textMuted),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: () => _editEntry(),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Add entry'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.featureVault,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'No entries in this category',
                              style: TextStyle(color: AppTheme.textMuted),
                            ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _entryTile(_entries[i]),
                    ),
        ),
      ],
    );
  }
}
