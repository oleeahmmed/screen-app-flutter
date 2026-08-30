import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/app_navigation.dart';
import '../services/user_data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_tab_shell.dart';
import '../widgets/tool_page_scaffold.dart';
import '../widgets/vault/vault_entry_detail_sheet.dart';
import '../widgets/vault/vault_helpers.dart';

/// Vault home — two tabs: **Vault** (category access) · **Shared with me** (entry shares).
class VaultHubPage extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback? onLogout;
  /// When true, omit ToolPageScaffold header (used as a main bottom tab).
  final bool embeddedInTabs;

  const VaultHubPage({
    super.key,
    required this.apiService,
    this.onLogout,
    this.embeddedInTabs = false,
  });

  @override
  State<VaultHubPage> createState() => _VaultHubPageState();
}

class _VaultHubPageState extends State<VaultHubPage> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  bool _loadingVault = true;
  bool _loadingShared = true;
  String? _vaultError;
  String? _sharedError;
  bool _isAdmin = false;
  int? _currentUserId;
  int _sharedCount = 0;
  List<Map<String, dynamic>> _vaults = [];
  List<Map<String, dynamic>> _sharedEntries = [];
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadUser();
    _loadAll();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  Future<void> _loadUser() async {
    final id = int.tryParse(await UserDataService.getUserId());
    if (mounted) setState(() => _currentUserId = id);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadVaultHub(), _loadShared()]);
  }

  Future<void> _loadVaultHub() async {
    setState(() {
      _loadingVault = true;
      _vaultError = null;
    });
    final r = await widget.apiService.getVaultMyHub();
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() {
        _loadingVault = false;
        _vaultError = r['error']?.toString() ?? 'Failed to load vaults';
      });
      return;
    }
    final data = Map<String, dynamic>.from(r['data'] as Map? ?? {});
    setState(() {
      _vaults = (data['vaults'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _isAdmin = data['is_admin'] == true;
      _sharedCount = data['shared_with_me_count'] is int
          ? data['shared_with_me_count'] as int
          : int.tryParse('${data['shared_with_me_count']}') ?? _sharedCount;
      _loadingVault = false;
    });
  }

  Future<void> _loadShared() async {
    setState(() {
      _loadingShared = true;
      _sharedError = null;
    });
    final r = await widget.apiService.getVaultSharedWithMe();
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() {
        _loadingShared = false;
        _sharedError = r['error']?.toString() ?? 'Failed to load shares';
      });
      return;
    }
    final results = (r['results'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    setState(() {
      _sharedEntries = results;
      _sharedCount = results.length;
      _loadingShared = false;
    });
  }

  List<Map<String, dynamic>> _filteredVaults() {
    if (_searchQuery.isEmpty) return _vaults;
    return _vaults.where((v) {
      final pname = (v['project_name'] ?? '').toString().toLowerCase();
      final cname = (v['customer_name'] ?? '').toString().toLowerCase();
      if (pname.contains(_searchQuery) || cname.contains(_searchQuery)) return true;
      final cats = v['categories'] as List? ?? [];
      for (final c in cats) {
        if (c is Map && (c['name'] ?? '').toString().toLowerCase().contains(_searchQuery)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  List<Map<String, dynamic>> _filteredShared() {
    if (_searchQuery.isEmpty) return _sharedEntries;
    return _sharedEntries.where((e) {
      final hay = [
        e['name'],
        e['username'],
        e['url'],
        e['category_name'],
        e['project_name'],
      ].map((x) => (x ?? '').toString().toLowerCase()).join(' ');
      return hay.contains(_searchQuery);
    }).toList();
  }

  void _openVault(Map<String, dynamic> vault) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppTabShell(
          selectedIndex: AppNavigation.instance.selectedTabIndex.clamp(0, AppNavigation.tabCount - 1),
          unreadNotifs: AppNavigation.instance.unreadNotifs,
          onLogout: widget.onLogout,
          child: VaultCategoriesPage(
            apiService: widget.apiService,
            vault: vault,
            onLogout: widget.onLogout,
          ),
        ),
      ),
    ).then((_) {
      if (mounted) _loadVaultHub();
    });
  }

  void _openSharedEntry(Map<String, dynamic> e) {
    final projectId = e['project'] is int
        ? e['project'] as int
        : int.tryParse('${e['project']}');
    if (projectId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppTabShell(
          selectedIndex: AppNavigation.instance.selectedTabIndex.clamp(0, AppNavigation.tabCount - 1),
          unreadNotifs: AppNavigation.instance.unreadNotifs,
          onLogout: widget.onLogout,
          child: VaultSharedEntryPage(
            apiService: widget.apiService,
            projectId: projectId,
            entry: e,
            canEdit: vaultEntryCanEdit(e, currentUserId: _currentUserId),
            currentUserId: _currentUserId,
            onLogout: widget.onLogout,
            onChanged: _loadShared,
          ),
        ),
      ),
    ).then((_) {
      if (mounted) _loadShared();
    });
  }

  Widget _segmentTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
      child: vaultSurfaceCard(
        padding: const EdgeInsets.all(5),
        child: TabBar(
          controller: _tabCtrl,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                AppTheme.featureVault.withValues(alpha: 0.42),
                AppTheme.featureVault.withValues(alpha: 0.2),
              ],
            ),
            border: Border.all(color: AppTheme.featureVault.withValues(alpha: 0.5)),
          ),
          labelColor: Colors.white,
          unselectedLabelColor: AppTheme.textMuted,
          labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          tabs: [
            const Tab(
              height: 42,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, size: 16),
                  SizedBox(width: 8),
                  Text('Vault'),
                ],
              ),
            ),
            Tab(
              height: 42,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_outline_rounded, size: 16),
                  const SizedBox(width: 8),
                  const Text('Shared'),
                  if (_sharedCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_sharedCount',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField(String hint) {
    return vaultSurfaceCard(
      padding: EdgeInsets.zero,
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.55)),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.85)),
          filled: true,
          fillColor: Colors.transparent,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: AppTheme.featureVault.withValues(alpha: 0.45)),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: vaultSurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              vaultIconBox(icon: icon, color: AppTheme.featureVault, size: 64, iconSize: 28, radius: 20),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textMuted.withValues(alpha: 0.9),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBox(String message, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: vaultSurfaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: AppTheme.danger.withValues(alpha: 0.85)),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.danger, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.featureVault),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vaultCard(Map<String, dynamic> vault) {
    final projectName = vault['project_name']?.toString() ?? 'Vault';
    final customerName = vault['customer_name']?.toString() ?? '';
    final catCount = vault['category_count'] ??
        (vault['categories'] as List? ?? []).length;
    final isAdmin = vault['is_admin'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openVault(vault),
          borderRadius: BorderRadius.circular(18),
          child: vaultSurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                vaultIconBox(
                  icon: Icons.shield_outlined,
                  color: AppTheme.featureVault,
                  size: 48,
                  iconSize: 24,
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
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (customerName.isNotEmpty) customerName,
                          '$catCount categor${catCount == 1 ? 'y' : 'ies'}',
                        ].join(' · '),
                        style: TextStyle(
                          color: AppTheme.textMuted.withValues(alpha: 0.9),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isAdmin) vaultPermissionChip('Admin', edit: true),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 22, color: AppTheme.textMuted.withValues(alpha: 0.45)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _vaultTab() {
    if (_loadingVault) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.featureVault));
    }
    if (_vaultError != null && _vaults.isEmpty) {
      return _errorBox(_vaultError!, _loadVaultHub);
    }

    final filtered = _filteredVaults();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchField('Search vault…'),
        const SizedBox(height: 16),
        if (filtered.isNotEmpty) ...[
          vaultSectionLabel('Choose a vault'),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: filtered.isEmpty
              ? _emptyState(
                  icon: Icons.lock_outline_rounded,
                  title: _searchQuery.isNotEmpty ? 'No matches' : 'No vault access',
                  message: _searchQuery.isNotEmpty
                      ? 'Try another search term.'
                      : (_isAdmin
                          ? 'Create categories inside a project vault.'
                          : 'When admin grants category access, your vaults appear here.'),
                )
              : RefreshIndicator(
                  onRefresh: _loadVaultHub,
                  color: AppTheme.featureVault,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.only(bottom: 28),
                    children: filtered.map(_vaultCard).toList(),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _sharedEntryTile(Map<String, dynamic> e) {
    final name = e['name']?.toString() ?? 'Entry';
    final user = e['username']?.toString() ?? '';
    final cat = e['category_name']?.toString() ?? '';
    final project = e['project_name']?.toString() ?? '';
    final meta = [
      if (project.isNotEmpty) project,
      if (cat.isNotEmpty) cat,
      if (user.isNotEmpty) user,
    ].join(' · ');
    final canEdit = vaultEntryCanEdit(e, currentUserId: _currentUserId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openSharedEntry(e),
          borderRadius: BorderRadius.circular(18),
          child: vaultSurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                vaultIconBox(
                  icon: vaultEntryIcon(e),
                  color: AppTheme.accent,
                  size: 46,
                  iconSize: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.textMuted.withValues(alpha: 0.9),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                vaultPermissionChip(
                  canEdit ? 'Can edit' : 'View only',
                  edit: canEdit,
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.45)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sharedTab() {
    if (_loadingShared) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    }
    if (_sharedError != null && _sharedEntries.isEmpty) {
      return _errorBox(_sharedError!, _loadShared);
    }

    final filtered = _filteredShared();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchField('Search shared credentials…'),
        const SizedBox(height: 16),
        if (filtered.isNotEmpty) ...[
          vaultSectionLabel('Shared with you'),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: filtered.isEmpty
              ? _emptyState(
                  icon: Icons.people_outline_rounded,
                  title: _searchQuery.isNotEmpty ? 'No matches' : 'Nothing shared yet',
                  message: _searchQuery.isNotEmpty
                      ? 'Try another search term.'
                      : 'When someone shares a credential with you, it appears here.',
                )
              : RefreshIndicator(
                  onRefresh: _loadShared,
                  color: AppTheme.accent,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.only(bottom: 28),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _sharedEntryTile(filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _segmentTabs(),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _vaultTab(),
              _sharedTab(),
            ],
          ),
        ),
      ],
    );

    if (widget.embeddedInTabs) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
        child: body,
      );
    }

    return ToolPageScaffold(
      title: 'Vault',
      subtitle: 'Your credentials, organized',
      onLogout: widget.onLogout,
      scrollable: false,
      child: body,
    );
  }
}

/// Step 2 — categories inside a chosen vault / project.
class VaultCategoriesPage extends StatelessWidget {
  final ApiService apiService;
  final Map<String, dynamic> vault;
  final VoidCallback? onLogout;

  const VaultCategoriesPage({
    super.key,
    required this.apiService,
    required this.vault,
    this.onLogout,
  });

  void _openCategory(BuildContext context, Map<String, dynamic> cat) {
    final projectId = vault['project_id'] is int
        ? vault['project_id'] as int
        : int.tryParse('${vault['project_id']}');
    if (projectId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppTabShell(
          selectedIndex: AppNavigation.instance.selectedTabIndex.clamp(0, AppNavigation.tabCount - 1),
          unreadNotifs: AppNavigation.instance.unreadNotifs,
          onLogout: onLogout,
          child: VaultCategoryPage(
            apiService: apiService,
            projectId: projectId,
            category: cat,
            vault: vault,
            onLogout: onLogout,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projectName = vault['project_name']?.toString() ?? 'Vault';
    final customerName = vault['customer_name']?.toString() ?? '';
    final categories = (vault['categories'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return ToolPageScaffold(
      title: '',
      showHeader: false,
      onLogout: onLogout,
      scrollable: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          vaultProjectHeader(
            projectName: projectName,
            customerName: customerName.isNotEmpty ? customerName : null,
            subtitle: '${categories.length} categor${categories.length == 1 ? 'y' : 'ies'}',
          ),
          const SizedBox(height: 16),
          if (categories.isEmpty)
            vaultSurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
              child: Text(
                'No categories in this vault',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9)),
              ),
            )
          else
            ...categories.map((cat) {
              final perm = vaultCategoryPermissionLabel(cat);
              final isEdit = perm == 'Can edit' || perm == 'Admin';
              final count = cat['entry_count'] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openCategory(context, cat),
                    borderRadius: BorderRadius.circular(18),
                    child: vaultSurfaceCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: Row(
                        children: [
                          vaultIconBox(
                            icon: Icons.folder_special_outlined,
                            color: AppTheme.featureVault,
                            size: 46,
                            iconSize: 22,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cat['name']?.toString() ?? 'Category',
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$count credential${count == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    color: AppTheme.textMuted.withValues(alpha: 0.85),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (perm.isNotEmpty) vaultPermissionChip(perm, edit: isEdit),
                          Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.45)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Category credentials — simple list under vault context.
class VaultCategoryPage extends StatefulWidget {
  final ApiService apiService;
  final int projectId;
  final Map<String, dynamic> category;
  final Map<String, dynamic> vault;
  final VoidCallback? onLogout;

  const VaultCategoryPage({
    super.key,
    required this.apiService,
    required this.projectId,
    required this.category,
    required this.vault,
    this.onLogout,
  });

  @override
  State<VaultCategoryPage> createState() => _VaultCategoryPageState();
}

class _VaultCategoryPageState extends State<VaultCategoryPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _entries = [];
  int? _currentUserId;

  int get _categoryId =>
      widget.category['id'] is int
          ? widget.category['id'] as int
          : int.parse('${widget.category['id']}');

  bool get _canAddEntries => vaultCanEditCategory(widget.category, isAdmin: widget.vault['is_admin'] == true);
  bool get _isVaultAdmin => widget.vault['is_admin'] == true;

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
    final r = await widget.apiService.getVaultEntries(
      widget.projectId,
      categoryId: _categoryId,
    );
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() {
        _loading = false;
        _error = r['error']?.toString() ?? 'Failed to load entries';
      });
      return;
    }
    setState(() {
      _entries = (r['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _loading = false;
    });
  }

  void _openEntry(Map<String, dynamic> e) {
    showVaultEntryDetailSheet(
      context: context,
      apiService: widget.apiService,
      projectId: widget.projectId,
      entry: e,
      isAdmin: _isVaultAdmin,
      canEdit: vaultEntryCanEdit(
        e,
        isVaultAdmin: _isVaultAdmin,
        currentUserId: _currentUserId,
      ),
      currentUserId: _currentUserId,
      onChanged: _load,
    );
  }

  Widget _hero() {
    final catName = widget.category['name']?.toString() ?? 'Category';
    final projectName = widget.vault['project_name']?.toString() ?? '';
    final customer = widget.vault['customer_name']?.toString() ?? '';
    final countLabel = _loading
        ? 'Loading credentials…'
        : '${_entries.length} credential${_entries.length == 1 ? '' : 's'}';

    return vaultContextBanner(
      projectName: projectName.isNotEmpty ? projectName : 'Vault',
      customerName: customer.isNotEmpty ? customer : null,
      categoryName: catName,
      subtitle: countLabel,
    );
  }

  Widget _entryCard(Map<String, dynamic> e) {
    final name = e['name']?.toString() ?? 'Entry';
    final user = e['username']?.toString() ?? '';
    final url = e['url']?.toString() ?? '';
    final subtitle = user.isNotEmpty ? user : (url.isNotEmpty ? url : 'Tap to view credentials');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openEntry(e),
          borderRadius: BorderRadius.circular(18),
          child: vaultSurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                vaultIconBox(
                  icon: vaultEntryIcon(e),
                  color: AppTheme.featureVault,
                  size: 46,
                  iconSize: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textMuted.withValues(alpha: 0.9),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.lock_open_rounded, size: 18, color: AppTheme.textMuted.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.45)),
              ],
            ),
          ),
          if (categories.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                'No categories shared yet',
                style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12.5),
              ),
            )
          else
            ...categories.map((cat) {
              final perm = vaultCategoryPermissionLabel(cat);
              final isEdit = perm == 'Edit' || perm == 'Admin';
              final count = cat['entry_count'] ?? 0;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openCategory(vault, cat),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 18,
                          color: AppTheme.featureVault.withValues(alpha: 0.75),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cat['name']?.toString() ?? 'Category',
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '$count entr${count == 1 ? 'y' : 'ies'}',
                                style: TextStyle(
                                  color: AppTheme.textMuted.withValues(alpha: 0.8),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (perm.isNotEmpty) vaultPermissionChip(perm, edit: isEdit),
                        const SizedBox(width: 6),
                        Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.45)),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _vaultTab() {
    if (_loadingVault) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.featureVault));
    }
    if (_vaultError != null && _vaults.isEmpty) {
      return _errorBox(_vaultError!, _loadVaultHub);
    }

    final filtered = _filteredVaults();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchField('Search vault or category…'),
        const SizedBox(height: 12),
        Expanded(
          child: filtered.isEmpty
              ? _emptyState(
                  icon: Icons.lock_outline_rounded,
                  title: _searchQuery.isNotEmpty ? 'No matches' : 'No vault access',
                  message: _searchQuery.isNotEmpty
                      ? 'Try another search term.'
                      : (_isAdmin
                          ? 'Create categories inside a project vault.'
                          : 'When admin grants category access, your vaults appear here.'),
                )
              : RefreshIndicator(
                  onRefresh: _loadVaultHub,
                  color: AppTheme.featureVault,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: filtered.map(_vaultCard).toList(),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _sharedEntryTile(Map<String, dynamic> e) {
    final name = e['name']?.toString() ?? 'Entry';
    final user = e['username']?.toString() ?? '';
    final cat = e['category_name']?.toString() ?? '';
    final project = e['project_name']?.toString() ?? '';
    final sharePerm = (e['share_permission'] ?? 'view').toString();
    final meta = [
      if (project.isNotEmpty) project,
      if (cat.isNotEmpty) cat,
      if (user.isNotEmpty) user,
    ].join(' · ');

    return Material(
      color: Colors.white.withValues(alpha: 0.035),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _openSharedEntry(e),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: AppTheme.accent.withValues(alpha: 0.14),
                ),
                child: Icon(vaultEntryIcon(e), size: 19, color: AppTheme.accent),
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
                        fontSize: 14.5,
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
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
              vaultPermissionChip(
                sharePerm.isEmpty
                    ? 'View'
                    : '${sharePerm[0].toUpperCase()}${sharePerm.substring(1)}',
                edit: sharePerm.toLowerCase() == 'edit',
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.45)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sharedTab() {
    if (_loadingShared) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    }
    if (_sharedError != null && _sharedEntries.isEmpty) {
      return _errorBox(_sharedError!, _loadShared);
    }

    final filtered = _filteredShared();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchField('Search shared entries…'),
        const SizedBox(height: 12),
        Expanded(
          child: filtered.isEmpty
              ? _emptyState(
                  icon: Icons.people_outline_rounded,
                  title: _searchQuery.isNotEmpty ? 'No matches' : 'Nothing shared yet',
                  message: _searchQuery.isNotEmpty
                      ? 'Try another search term.'
                      : 'When someone shares a specific credential with you, it appears here.',
                )
              : RefreshIndicator(
                  onRefresh: _loadShared,
                  color: AppTheme.accent,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _sharedEntryTile(filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ToolPageScaffold(
      title: 'Vault',
      subtitle: 'Your credentials, organized',
      onLogout: widget.onLogout,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _segmentTabs(),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _vaultTab(),
                _sharedTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Category entry list — tap an entry to reveal / copy credentials.
class VaultCategoryPage extends StatefulWidget {
  final ApiService apiService;
  final int projectId;
  final Map<String, dynamic> category;
  final Map<String, dynamic> vault;
  final VoidCallback? onLogout;

  const VaultCategoryPage({
    super.key,
    required this.apiService,
    required this.projectId,
    required this.category,
    required this.vault,
    this.onLogout,
  });

  @override
  State<VaultCategoryPage> createState() => _VaultCategoryPageState();
}

class _VaultCategoryPageState extends State<VaultCategoryPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _entries = [];

  int get _categoryId =>
      widget.category['id'] is int
          ? widget.category['id'] as int
          : int.parse('${widget.category['id']}');

  bool get _canEdit => vaultCanEditCategory(widget.category, isAdmin: widget.vault['is_admin'] == true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await widget.apiService.getVaultEntries(
      widget.projectId,
      categoryId: _categoryId,
    );
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() {
        _loading = false;
        _error = r['error']?.toString() ?? 'Failed to load entries';
      });
      return;
    }
    setState(() {
      _entries = (r['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _loading = false;
    });
  }

  void _openEntry(Map<String, dynamic> e) {
    showVaultEntryDetailSheet(
      context: context,
      apiService: widget.apiService,
      projectId: widget.projectId,
      entry: e,
      isAdmin: widget.vault['is_admin'] == true,
      canEdit: _canEdit,
      onChanged: _load,
    );
  }

  Widget _entryTile(Map<String, dynamic> e) {
    final name = e['name']?.toString() ?? 'Entry';
    final user = e['username']?.toString() ?? '';
    final url = e['url']?.toString() ?? '';
    final subtitle = user.isNotEmpty ? user : (url.isNotEmpty ? url : 'Tap to open');

    return Material(
      color: Colors.white.withValues(alpha: 0.035),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _openEntry(e),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: AppTheme.featureVault.withValues(alpha: 0.14),
                ),
                child: Icon(vaultEntryIcon(e), size: 19, color: AppTheme.featureVault),
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
                        fontSize: 14.5,
                      ),
                    ),
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
              Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.45)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catName = widget.category['name']?.toString() ?? 'Category';
    final projectName = widget.vault['project_name']?.toString() ?? '';
    final perm = vaultCategoryPermissionLabel(widget.category);

    return ToolPageScaffold(
      title: '',
      showHeader: false,
      onLogout: widget.onLogout,
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: AppTheme.featureVault)))
          else if (_error != null)
            Expanded(
              child: Center(
                child: vaultSurfaceCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off_outlined, size: 40, color: AppTheme.danger.withValues(alpha: 0.85)),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.danger)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.featureVault),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: AppTheme.featureVault,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.only(bottom: 28),
                  children: [
                    _hero(),
                    const SizedBox(height: 16),
                    if (_entries.isEmpty)
                      vaultSurfaceCard(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                        child: Column(
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 40,
                              color: AppTheme.featureVault.withValues(alpha: 0.55),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No entries yet',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _canAddEntries
                                  ? 'Open this project’s Vault tab to add credentials.'
                                  : 'Nothing has been added to this category yet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.textMuted.withValues(alpha: 0.9),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._entries.map(_entryCard),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-page shared credential — profile form look.
class VaultSharedEntryPage extends StatelessWidget {
  final ApiService apiService;
  final int projectId;
  final Map<String, dynamic> entry;
  final bool canEdit;
  final int? currentUserId;
  final VoidCallback? onLogout;
  final VoidCallback onChanged;

  const VaultSharedEntryPage({
    super.key,
    required this.apiService,
    required this.projectId,
    required this.entry,
    required this.canEdit,
    this.currentUserId,
    this.onLogout,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final name = entry['name']?.toString() ?? 'Credential';
    final project = entry['project_name']?.toString() ?? '';
    final cat = entry['category_name']?.toString() ?? '';
    final subtitle = [
      if (project.isNotEmpty) project,
      if (cat.isNotEmpty) cat,
    ].join(' · ');
    final effectiveCanEdit = vaultEntryCanEdit(
      entry,
      currentUserId: currentUserId,
    );

    return ToolPageScaffold(
      title: '',
      showHeader: false,
      onLogout: onLogout,
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.accent.withValues(alpha: 0.95),
                              AppTheme.primary.withValues(alpha: 0.75),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.35),
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(3),
                        child: CircleAvatar(
                          backgroundColor: AppTheme.bgDeep,
                          child: Icon(vaultEntryIcon(entry), color: AppTheme.accent, size: 34),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textMuted.withValues(alpha: 0.95),
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      vaultPermissionChip(
                        effectiveCanEdit ? 'Can edit' : 'View only',
                        edit: effectiveCanEdit,
                      ),
                      const SizedBox(height: 8),
                      vaultRoleBadge(isAdmin: false),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                vaultSectionLabel('Credential details'),
                const SizedBox(height: 10),
                VaultEntryDetailForm(
                  apiService: apiService,
                  projectId: projectId,
                  entry: entry,
                  isAdmin: false,
                  canEdit: effectiveCanEdit,
                  currentUserId: currentUserId,
                  onChanged: onChanged,
                  embedded: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
