import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api_service.dart';
import '../services/app_navigation.dart';
import '../services/user_data_service.dart';
import '../theme/app_theme.dart';
import '../theme/vault_theme.dart';
import '../utils/platform_capabilities.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_tab_shell.dart';
import '../widgets/project_vault_tab.dart';
import '../widgets/tool_page_scaffold.dart';
import '../widgets/vault/vault_entry_detail_sheet.dart';
import '../widgets/vault/vault_helpers.dart';

/// Vault home — project cards; tap a project for categories (same flow as aims-webapps).
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

class _VaultHubPageState extends State<VaultHubPage> {
  bool _loadingVault = true;
  String? _vaultError;
  bool _isAdmin = false;
  List<Map<String, dynamic>> _vaults = [];
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadVaultHub();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
      _loadingVault = false;
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

  void _openVault(Map<String, dynamic> vault) {
    final projectId = vault['project_id'] is int
        ? vault['project_id'] as int
        : int.tryParse('${vault['project_id']}');
    if (projectId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppTabShell(
          selectedIndex: AppNavigation.instance.selectedTabIndex.clamp(0, AppNavigation.tabCount - 1),
          unreadNotifs: AppNavigation.instance.unreadNotifs,
          onLogout: widget.onLogout,
          child: ToolPageScaffold(
            title: vault['project_name']?.toString() ?? 'Vault',
            showHeader: false,
            onLogout: widget.onLogout,
            scrollable: false,
            child: ProjectVaultTab(
              apiService: widget.apiService,
              projectId: projectId,
            ),
          ),
        ),
      ),
    ).then((_) {
      if (mounted) _loadVaultHub();
    });
  }

  Widget _searchField(String hint) {
    return VaultTheme.searchField(
      controller: _searchCtrl,
      onChanged: (_) => setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase()),
      hint: hint,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VaultTheme.iconBox(icon: icon, color: VaultTheme.violet, size: 56, iconSize: 24),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openVault(vault),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.loginInsetDecoration(borderRadius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  VaultTheme.iconBox(
                    icon: LucideIcons.folderLock,
                    color: VaultTheme.violet,
                    size: 40,
                    iconSize: 18,
                  ),
                  const Spacer(),
                  if (isAdmin)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: VaultTheme.violet.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: VaultTheme.violet.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'Admin',
                        style: TextStyle(
                          color: VaultTheme.violetBright,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                projectName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.2,
                  letterSpacing: -0.2,
                ),
              ),
              if (customerName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textMuted.withValues(alpha: 0.92),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    LucideIcons.layers,
                    size: 13,
                    color: VaultTheme.violetBright.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '$catCount categor${catCount == 1 ? 'y' : 'ies'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: VaultTheme.violetBright.withValues(alpha: 0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: AppTheme.textMuted.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _projectGrid({bool includeSearch = true}) {
    if (_loadingVault) {
      return const Center(child: CircularProgressIndicator(color: VaultTheme.violet));
    }
    if (_vaultError != null && _vaults.isEmpty) {
      return _errorBox(_vaultError!, _loadVaultHub);
    }

    final filtered = _filteredVaults();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (includeSearch) ...[
          _searchField('Search projects…'),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: filtered.isEmpty
              ? _emptyState(
                  icon: LucideIcons.shield,
                  title: _searchQuery.isNotEmpty ? 'No matches' : 'No vault access',
                  message: _searchQuery.isNotEmpty
                      ? 'Try another search term.'
                      : (_isAdmin
                          ? 'Create categories inside a project vault.'
                          : 'When admin grants category access, your vaults appear here.'),
                )
              : RefreshIndicator(
                  onRefresh: _loadVaultHub,
                  color: VaultTheme.violet,
                  backgroundColor: VaultTheme.modalBg,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final crossAxisCount = width >= 720 ? 3 : (width >= 380 ? 2 : 1);
                      const gap = 12.0;

                      return GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        padding: const EdgeInsets.only(bottom: 28),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: gap,
                          crossAxisSpacing: gap,
                          childAspectRatio: crossAxisCount == 1 ? 2.35 : 0.88,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _vaultCard(filtered[i]),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _logoButton() {
    return Tooltip(
      message: 'Dashboard',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => AppNavigation.instance.goHome(),
          borderRadius: BorderRadius.circular(10),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: AppLogo(size: 30, showBorder: false),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool immersive, double sidePad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(sidePad, immersive ? 4 : 8, sidePad, 8),
      child: AppTheme.glassCard(
        borderRadius: 18,
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (immersive)
              IconButton(
                tooltip: 'Home',
                onPressed: () => AppNavigation.instance.goHome(),
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
                  const Text(
                    'Vault',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Secure credentials by project',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textMuted.withValues(alpha: 0.92),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loadVaultHub,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh_rounded, size: 22, color: AppTheme.textMuted),
            ),
            if (immersive) _logoButton(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final immersive = widget.embeddedInTabs && PlatformCapabilities.immersiveChatChrome;
    const sidePad = 12.0;

    if (immersive) {
      final bottomInset = MediaQuery.paddingOf(context).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(true, sidePad),
              Padding(
                padding: const EdgeInsets.fromLTRB(sidePad, 4, sidePad, 8),
                child: _searchField('Search projects…'),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: sidePad),
                  child: _projectGrid(includeSearch: false),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final body = _projectGrid();

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
class VaultCategoriesPage extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> vault;
  final VoidCallback? onLogout;

  const VaultCategoriesPage({
    super.key,
    required this.apiService,
    required this.vault,
    this.onLogout,
  });

  @override
  State<VaultCategoriesPage> createState() => _VaultCategoriesPageState();
}

class _VaultCategoriesPageState extends State<VaultCategoriesPage> {
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openCategory(BuildContext context, Map<String, dynamic> cat) {
    final projectId = widget.vault['project_id'] is int
        ? widget.vault['project_id'] as int
        : int.tryParse('${widget.vault['project_id']}');
    if (projectId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppTabShell(
          selectedIndex: AppNavigation.instance.selectedTabIndex.clamp(0, AppNavigation.tabCount - 1),
          unreadNotifs: AppNavigation.instance.unreadNotifs,
          onLogout: widget.onLogout,
          child: VaultCategoryPage(
            apiService: widget.apiService,
            projectId: projectId,
            category: cat,
            vault: widget.vault,
            onLogout: widget.onLogout,
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filteredCategories(List<Map<String, dynamic>> categories) {
    if (_searchQuery.isEmpty) return categories;
    return categories.where((cat) {
      return (cat['name'] ?? '').toString().toLowerCase().contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final projectName = widget.vault['project_name']?.toString() ?? 'Vault';
    final customerName = widget.vault['customer_name']?.toString() ?? '';
    final categories = (widget.vault['categories'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final filtered = _filteredCategories(categories);

    return ToolPageScaffold(
      title: '',
      showHeader: false,
      onLogout: widget.onLogout,
      scrollable: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
        children: [
          vaultProjectHeader(
            projectName: projectName,
            customerName: customerName.isNotEmpty ? customerName : null,
            subtitle: '${categories.length} categor${categories.length == 1 ? 'y' : 'ies'}',
          ),
          const SizedBox(height: 14),
          if (categories.isNotEmpty)
            VaultTheme.searchField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase()),
              hint: 'Search categories…',
            ),
          const SizedBox(height: 12),
          if (categories.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
              decoration: VaultTheme.cardSurface(),
              child: Text(
                'No categories in this vault',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9)),
              ),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No categories match your search.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9)),
              ),
            )
          else
            ...filtered.map((cat) {
              final perm = vaultCategoryPermissionLabel(cat);
              final isEdit = vaultCategoryPermissionIsEdit(cat);
              final count = cat['entry_count'] ?? 0;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openCategory(context, cat),
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
                          icon: LucideIcons.folderLock,
                          color: VaultTheme.violet,
                          size: 48,
                          iconSize: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cat['name']?.toString() ?? 'Category',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$count credential${count == 1 ? '' : 's'}',
                                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
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
  String _searchQuery = '';
  String _filter = 'all';
  String? _letter;
  final _searchCtrl = TextEditingController();

  int get _categoryId =>
      widget.category['id'] is int
          ? widget.category['id'] as int
          : int.parse('${widget.category['id']}');

  bool get _isVaultAdmin => widget.vault['is_admin'] == true;
  bool get _canAddEntries => vaultCanEditCategory(widget.category, isAdmin: _isVaultAdmin);
  bool get _catAdmin => vaultCategoryCanAdmin(widget.category, projectVaultAdmin: _isVaultAdmin);

  @override
  void initState() {
    super.initState();
    _loadUser();
    _load();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int get _createdCount =>
      _entries.where((e) => VaultTheme.isCreatedByMe(e, _currentUserId)).length;

  int get _sharedCount => _entries.length - _createdCount;

  List<Map<String, dynamic>> _filteredEntries() {
    var list = List<Map<String, dynamic>>.from(_entries);
    if (_filter == 'created-by-me') {
      list = list.where((e) => VaultTheme.isCreatedByMe(e, _currentUserId)).toList();
    } else if (_filter == 'shared-to-me') {
      list = list.where((e) => !VaultTheme.isCreatedByMe(e, _currentUserId)).toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list.where((e) {
        final hay = [e['name'], e['username'], e['url']]
            .map((x) => (x ?? '').toString().toLowerCase())
            .join(' ');
        return hay.contains(_searchQuery);
      }).toList();
    }
    if (_letter != null) {
      list = list.where((e) {
        final name = (e['name'] ?? '').toString();
        if (name.isEmpty) return _letter == '#';
        final first = name[0].toUpperCase();
        if (_letter == '#') return !RegExp(r'^[A-Z]').hasMatch(first);
        return first == _letter;
      }).toList();
    }
    list.sort(
      (a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()),
    );
    return list;
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
    final entry = vaultEntryWithCategoryPerm(e, widget.category);
    showVaultEntryDetailSheet(
      context: context,
      apiService: widget.apiService,
      projectId: widget.projectId,
      entry: entry,
      isAdmin: _isVaultAdmin || _catAdmin,
      canEdit: vaultCanEditCategory(widget.category, isAdmin: _isVaultAdmin),
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
    final createdByMe = VaultTheme.isCreatedByMe(e, _currentUserId);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openEntry(e),
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
                color: createdByMe ? VaultTheme.violet : VaultTheme.sharedBlue,
                size: 48,
                iconSize: 22,
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
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (createdByMe) VaultTheme.createdByBadge() else VaultTheme.sharedBadge(),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textMuted.withValues(alpha: 0.45)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filtersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VaultTheme.filterBar(
          active: _filter,
          onChanged: (v) => setState(() => _filter = v),
          allCount: _entries.length,
          createdCount: _createdCount,
          sharedCount: _sharedCount,
        ),
        const SizedBox(height: 10),
        VaultTheme.searchField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase()),
          hint: 'Search credentials…',
        ),
        const SizedBox(height: 10),
        VaultTheme.letterPicker(
          active: _letter,
          onChanged: (v) => setState(() => _letter = v),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEntries();
    return ToolPageScaffold(
      title: '',
      showHeader: false,
      onLogout: widget.onLogout,
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: VaultTheme.violet)))
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
                        style: FilledButton.styleFrom(backgroundColor: VaultTheme.violet),
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
                color: VaultTheme.violet,
                backgroundColor: VaultTheme.modalBg,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
                  children: [
                    _hero(),
                    const SizedBox(height: 14),
                    if (_entries.isNotEmpty) _filtersSection(),
                    const SizedBox(height: 12),
                    if (_entries.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                        decoration: VaultTheme.cardSurface(),
                        child: Column(
                          children: [
                            VaultTheme.iconBox(
                              icon: LucideIcons.keyRound,
                              color: VaultTheme.violet,
                              size: 56,
                              iconSize: 24,
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
                    else if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No credentials match your filters.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9)),
                        ),
                      )
                    else
                      ...filtered.map(_entryCard),
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
    final effectiveCanEdit = false; // Shared credential page is view-only
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
                      vaultPermissionChip('View only', edit: false),
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
