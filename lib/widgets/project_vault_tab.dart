import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api_service.dart';
import '../services/user_data_service.dart';
import '../theme/app_theme.dart';
import '../theme/vault_theme.dart';
import '../utils/app_toast.dart';
import '../utils/vault_models.dart';
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
  bool _vaultPrivileged = false;
  bool _canCreateCategory = false;
  int? _currentUserId;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _entries = [];
  int? _categoryId;
  int _segmentTab = 0; // 0 my vault, 1 shared
  String _categoryFilter = 'all';
  String _entryFilter = 'all';
  String _search = '';
  String? _letter;
  bool _sharedLoading = false;
  List<Map<String, dynamic>> _sharedEntries = [];
  String _projectName = 'Vault';
  String _customerName = '';
  final _searchCtrl = TextEditingController();

  Map<String, dynamic>? get _selectedCat {
    if (_categoryId == null) return null;
    for (final c in _categories) {
      if (c['id'] == _categoryId) return c;
    }
    return null;
  }

  bool _canEditCat(Map<String, dynamic>? c) =>
      vaultCanEditCategory(c, isAdmin: _vaultPrivileged);

  bool _catCanAdmin(Map<String, dynamic>? c) =>
      vaultCategoryCanAdmin(c, projectVaultAdmin: _vaultPrivileged);

  @override
  void initState() {
    super.initState();
    _loadUser();
    _load();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
    final vaultPrivileged = companyPrivileged || project['is_manager'] == true;
    final members = (project['project_members'] as List?) ?? [];
    final uid = _currentUserId;
    final isMember = uid != null && members.any((m) {
      if (m is! Map) return false;
      final u = m['user'];
      final id = m['user_id'] ?? (u is Map ? u['id'] : null);
      return id == uid;
    });

    int? selected = widget.initialCategoryId ?? _categoryId;
    if (widget.lockToCategory && selected != null && !cats.any((c) => c['id'] == selected)) {
      selected = null;
    }
    if (!widget.lockToCategory) {
      selected = widget.initialCategoryId;
      if (selected != null && !cats.any((c) => c['id'] == selected)) selected = null;
    }

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
      _vaultPrivileged = vaultPrivileged;
      _canCreateCategory = vaultPrivileged || isMember;
      _categoryId = selected;
      _entries = entries;
      _loading = false;
      _error = entryErr;
      _projectName = project['name']?.toString() ?? 'Vault';
      _customerName = project['customer_name']?.toString() ?? '';
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

  Future<void> _loadShared() async {
    setState(() => _sharedLoading = true);
    final r = await widget.apiService.getVaultSharedWithMe(projectId: widget.projectId);
    if (!mounted) return;
    setState(() {
      _sharedLoading = false;
      _sharedEntries = r['success'] == true
          ? (r['results'] as List? ?? r['data']?['results'] as List? ?? [])
              .whereType<Map>()
              .map((e) => normalizeVaultEntry(Map<String, dynamic>.from(e)))
              .toList()
          : [];
    });
  }

  void _openCategory(Map<String, dynamic> cat) {
    final id = cat['id'] is int ? cat['id'] as int : int.parse('${cat['id']}');
    _selectCategory(id);
  }

  void _backToCategories() {
    setState(() {
      _categoryId = null;
      _entries = [];
      _entryFilter = 'all';
      _letter = null;
      _searchCtrl.clear();
      _search = '';
    });
  }

  List<Map<String, dynamic>> _filteredCategories() {
    return _categories.where((cat) {
      final mine = vaultIsCreatedBy(cat, _currentUserId);
      if (_categoryFilter == 'created-by-me' && !mine) return false;
      if (_categoryFilter == 'shared-to-me' && mine) return false;
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> _filteredEntries() {
    return _entries.where((e) {
      final mine = vaultIsCreatedBy(e, _currentUserId);
      if (_entryFilter == 'created-by-me' && !mine) return false;
      if (_entryFilter == 'shared-to-me' && mine) return false;
      if (_search.isNotEmpty) {
        final hay = '${e['name']} ${e['url']} ${e['username']} ${e['notes']}'.toLowerCase();
        if (!hay.contains(_search)) return false;
      }
      if (_letter != null) {
        final name = (e['name'] ?? '').toString();
        final first = name.isNotEmpty ? name[0].toUpperCase() : '';
        if (_letter == '#') {
          if (RegExp(r'^[A-Z]').hasMatch(first)) return false;
        } else if (first != _letter) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> _filteredShared() {
    if (_search.isEmpty) return _sharedEntries;
    return _sharedEntries.where((e) {
      final hay = '${e['name']} ${e['username']} ${e['category_name']}'.toLowerCase();
      return hay.contains(_search);
    }).toList();
  }

  Widget _projectVaultHero() {
    final inCategory = _categoryId != null;
    final catName = _selectedCat?['name']?.toString() ?? '';
    final subtitle = inCategory
        ? (catName.isNotEmpty ? 'Category · $catName' : 'Category')
        : [
            if (_customerName.isNotEmpty) _customerName,
            '${_categories.length} categor${_categories.length == 1 ? 'y' : 'ies'}',
          ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: AppTheme.glassCard(
        borderRadius: 18,
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (inCategory && !widget.lockToCategory)
              IconButton(
                tooltip: 'Back to categories',
                onPressed: _backToCategories,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppTheme.textPrimary),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            VaultTheme.iconBox(
              icon: LucideIcons.shield,
              color: AppTheme.featureVault,
              size: 42,
              iconSize: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _projectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textMuted.withValues(alpha: 0.92),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh_rounded, size: 22, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segmentTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: VaultTheme.topTab(
              label: 'My Vault',
              icon: LucideIcons.shield,
              active: _segmentTab == 0,
              sharedTone: false,
              onTap: () => setState(() => _segmentTab = 0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: VaultTheme.topTab(
              label: 'Shared with me',
              icon: LucideIcons.share2,
              active: _segmentTab == 1,
              sharedTone: true,
              badge: _sharedEntries.length,
              onTap: () {
                setState(() => _segmentTab = 1);
                if (_sharedEntries.isEmpty && !_sharedLoading) _loadShared();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _vaultActionButton({
    required VoidCallback onTap,
    required String label,
    required IconData icon,
    bool compact = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 7 : 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.featureVault.withValues(alpha: 0.22),
                AppTheme.featureVault.withValues(alpha: 0.1),
              ],
            ),
            border: Border.all(color: AppTheme.featureVault.withValues(alpha: 0.38)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 15 : 16, color: VaultTheme.violetBright),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: VaultTheme.violetBright,
                  fontSize: compact ? 11.5 : 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categoriesSectionHeader({
    required int created,
    required int shared,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: AppTheme.glassCard(
        borderRadius: 16,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                VaultTheme.iconBox(
                  icon: LucideIcons.layers,
                  color: VaultTheme.violet,
                  size: 38,
                  iconSize: 17,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Categories',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          letterSpacing: -0.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_categories.length} total · $created yours · $shared shared',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textMuted.withValues(alpha: 0.9),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_canCreateCategory) ...[
                  const SizedBox(width: 8),
                  _vaultActionButton(
                    onTap: () => _editCategory(),
                    label: 'New',
                    icon: Icons.add_rounded,
                    compact: true,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            VaultTheme.filterBar(
              active: _categoryFilter,
              onChanged: (v) => setState(() => _categoryFilter = v),
              allCount: _categories.length,
              createdCount: created,
              sharedCount: shared,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCategoriesState() {
    final filtered = _categoryFilter != 'all';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VaultTheme.iconBox(
              icon: LucideIcons.folderLock,
              color: VaultTheme.violet,
              size: 56,
              iconSize: 24,
            ),
            const SizedBox(height: 16),
            Text(
              filtered ? 'No categories in this filter' : 'No categories yet',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'Try another filter or create a new category.'
                  : 'Organize credentials into folders your team can access.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textMuted.withValues(alpha: 0.92),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            if (_canCreateCategory && !filtered) ...[
              const SizedBox(height: 18),
              _vaultActionButton(
                onTap: () => _editCategory(),
                label: 'Create category',
                icon: Icons.add_rounded,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _categoryGrid() {
    final filtered = _filteredCategories();
    final created = _categories.where((c) => vaultIsCreatedBy(c, _currentUserId)).length;
    final shared = _categories.length - created;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _categoriesSectionHeader(created: created, shared: shared),
        Expanded(
          child: filtered.isEmpty
              ? _emptyCategoriesState()
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.22,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final cat = filtered[i];
                    final mine = vaultIsCreatedBy(cat, _currentUserId);
                    final count = cat['entry_count'] ?? 0;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openCategory(cat),
                        onLongPress: _catCanAdmin(cat) ? () => _categoryMenu(cat) : null,
                        borderRadius: BorderRadius.circular(14),
                        child: Ink(
                          padding: const EdgeInsets.all(12),
                          decoration: AppTheme.loginInsetDecoration(borderRadius: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  VaultTheme.iconBox(
                                    icon: LucideIcons.folderLock,
                                    color: VaultTheme.violet,
                                    size: 32,
                                    iconSize: 15,
                                  ),
                                  const Spacer(),
                                  if (mine)
                                    VaultTheme.createdByBadge()
                                  else
                                    VaultTheme.sharedBadge(),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                cat['name']?.toString() ?? 'Category',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    LucideIcons.keyRound,
                                    size: 12,
                                    color: VaultTheme.violetBright.withValues(alpha: 0.85),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '$count entr${count == 1 ? 'y' : 'ies'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppTheme.textMuted.withValues(alpha: 0.9),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 12,
                                    color: AppTheme.textMuted.withValues(alpha: 0.45),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _entriesSectionHeader({
    required Map<String, dynamic>? cat,
    required bool canEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: AppTheme.glassCard(
        borderRadius: 16,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Row(
          children: [
            VaultTheme.iconBox(
              icon: LucideIcons.keyRound,
              color: VaultTheme.violet,
              size: 38,
              iconSize: 17,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cat?['name']?.toString() ?? 'Category',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_entries.length} credential${_entries.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: AppTheme.textMuted.withValues(alpha: 0.9),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (canEdit)
              _vaultActionButton(
                onTap: () => _editEntry(),
                label: 'Entry',
                icon: Icons.add_rounded,
                compact: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _entryListView() {
    final cat = _selectedCat;
    final canEdit = _canEditCat(cat);
    final created = _entries.where((e) => vaultIsCreatedBy(e, _currentUserId)).length;
    final shared = _entries.length - created;
    final filtered = _filteredEntries();
    final letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#'.split('');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entriesSectionHeader(cat: cat, canEdit: canEdit),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: AppTheme.glassCard(
            borderRadius: 16,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VaultTheme.searchField(
                  controller: _searchCtrl,
                  hint: 'Search entries…',
                  onChanged: (_) => setState(() => _search = _searchCtrl.text.trim().toLowerCase()),
                ),
                const SizedBox(height: 10),
                VaultTheme.filterBar(
                  active: _entryFilter,
                  onChanged: (v) => setState(() => _entryFilter = v),
                  allCount: _entries.length,
                  createdCount: created,
                  sharedCount: shared,
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: letters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (_, i) {
              final l = letters[i];
              final active = _letter == l;
              return FilterChip(
                label: Text(l, style: const TextStyle(fontSize: 11)),
                selected: active,
                onSelected: (_) => setState(() => _letter = active ? null : l),
                visualDensity: VisualDensity.compact,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: canEdit
                      ? _vaultActionButton(
                          onTap: () => _editEntry(),
                          label: 'Add entry',
                          icon: Icons.add_rounded,
                        )
                      : const Text(
                          'No entries in this category',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _entryTile(filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _sharedListView() {
    if (_sharedLoading) return const Center(child: CircularProgressIndicator(color: VaultTheme.sharedBlue));
    final filtered = _filteredShared();
    return Column(
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: VaultTheme.searchField(controller: _searchCtrl, hint: 'Search shared credentials…', onChanged: (_) => setState(() => _search = _searchCtrl.text.trim().toLowerCase()))),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Nothing shared with you in this project', style: TextStyle(color: AppTheme.textMuted)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _entryTile(filtered[i], sharedInbox: true),
                ),
        ),
      ],
    );
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
    if (existing != null && !_catCanAdmin(existing)) return;
    if (existing == null && !_canCreateCategory) return;
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
    if (!_catCanAdmin(cat)) return;
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
    if (!_catCanAdmin(cat)) return;
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
      _toast('You do not have permission to add or edit entries', error: true);
      return;
    }
    if (cat == null) {
      _toast('Create a category first', error: true);
      return;
    }
    final catId = cat['id'] as int;
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

  void _openEntryDetail(Map<String, dynamic> e, {bool sharedInbox = false}) {
    final entry = sharedInbox ? e : vaultEntryWithCategoryPerm(e, _selectedCat);
    showVaultEntryDetailSheet(
      context: context,
      apiService: widget.apiService,
      projectId: widget.projectId,
      entry: entry,
      isAdmin: _vaultPrivileged || _catCanAdmin(_selectedCat),
      canEdit: sharedInbox ? false : _canEditCat(_selectedCat),
      currentUserId: _currentUserId,
      onChanged: () {
        if (sharedInbox) {
          _loadShared();
        } else if (_categoryId != null) {
          _selectCategory(_categoryId!);
        }
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
    final permLabel = _catCanAdmin(c) ? '' : vaultCategoryPermissionLabel(c);
    final isEdit = !_catCanAdmin(c) && vaultCategoryPermissionIsEdit(c);

    return Material(
      color: selected
          ? VaultTheme.violet.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _selectCategory(id),
        onLongPress: _catCanAdmin(c) ? () => _categoryMenu(c) : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.fromLTRB(14, 10, _catCanAdmin(c) ? 6 : 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? VaultTheme.violet.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.08),
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
              if (_catCanAdmin(c))
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

  Widget _entryTile(Map<String, dynamic> e, {bool sharedInbox = false}) {
    final name = e['name']?.toString() ?? 'Entry';
    final user = e['username']?.toString() ?? '';
    final url = e['url']?.toString() ?? '';
    final subtitle = user.isNotEmpty
        ? user
        : (url.isNotEmpty ? url : 'Tap to view credentials');

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _openEntryDetail(e, sharedInbox: sharedInbox),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: Row(
            children: [
              VaultTheme.iconBox(
                icon: vaultEntryIcon(e),
                color: VaultTheme.isCreatedByMe(e, _currentUserId) ? VaultTheme.violet : VaultTheme.sharedBlue,
                size: 44,
                iconSize: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
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
              if (VaultTheme.isCreatedByMe(e, _currentUserId))
                VaultTheme.createdByBadge()
              else if (_currentUserId != null)
                VaultTheme.sharedBadge(),
              const SizedBox(width: 4),
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

    if (widget.lockToCategory && _categoryId != null) {
      return _entryListView();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.lockToCategory) ...[
          _projectVaultHero(),
          _segmentTabs(),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
          ),
        Expanded(
          child: _segmentTab == 1
              ? _sharedListView()
              : (_categoryId == null ? _categoryGrid() : _entryListView()),
        ),
      ],
    );
  }
}
