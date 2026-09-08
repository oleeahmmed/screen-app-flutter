import '../utils/vault_models.dart';
import 'api_service.dart';
import 'user_data_service.dart';

/// Client-side vault hub — same strategy as aims-webapps (project-scoped APIs).
///
/// Web never calls `/api/projects/vault/my/`; it loads
/// `/api/projects/{id}/vault/categories/` per project.
class VaultHubLoader {
  VaultHubLoader(this._api);

  final ApiService _api;

  static bool isAccessesFieldError(String? message) {
    if (message == null || message.isEmpty) return false;
    final lower = message.toLowerCase();
    return lower.contains("keyword 'accesses'") ||
        (lower.contains('cannot resolve keyword') && lower.contains('accesses'));
  }

  /// My vault hub — projects + category counts (parallel fetch, no shared inbox).
  Future<Map<String, dynamic>> composeMyHub() async {
    final companyAdmin = await UserDataService.isCompanyAdmin();
    final projects = await _loadProjects();
    var anyAdmin = companyAdmin;

    final vaultRows = await Future.wait(
      projects.map((project) async {
        final projectId = _int(project['id']);
        if (projectId == null) return null;

        final catR = await _api.getVaultCategories(projectId);
        if (catR['success'] != true) return null;

        final categories = (catR['data'] as List? ?? [])
            .whereType<Map>()
            .map((c) => normalizeVaultCategory(Map<String, dynamic>.from(c)))
            .toList();

        final isProjectAdmin = categories.any(
          (c) => c['my_permission'] == 'admin' || c['can_admin'] == true,
        );

        return {
          'project_id': projectId,
          'project_name': project['name']?.toString() ?? 'Project',
          'customer_id': _int(project['customer_id']),
          'customer_name': project['customer_name']?.toString() ?? '',
          'is_admin': isProjectAdmin || companyAdmin,
          'category_count': categories.length,
          'categories': categories,
          '_project_admin': isProjectAdmin,
        };
      }),
    );

    final vaults = vaultRows.whereType<Map<String, dynamic>>().toList();
    for (final v in vaults) {
      if (v['_project_admin'] == true) anyAdmin = true;
      v.remove('_project_admin');
    }

    vaults.sort((a, b) {
      final c = (a['customer_name'] ?? '').toString().compareTo(
            (b['customer_name'] ?? '').toString(),
          );
      if (c != 0) return c;
      return (a['project_name'] ?? '').toString().compareTo(
            (b['project_name'] ?? '').toString(),
          );
    });

    return {
      'success': true,
      'data': {
        'is_admin': anyAdmin,
        'vault_count': vaults.length,
        'shared_with_me_count': 0,
        'vaults': vaults,
      },
    };
  }

  /// Shared inbox — project-scoped like aims-webapps `getSharedWithMe({ project_id })`.
  Future<Map<String, dynamic>> composeSharedInbox({int? projectId}) async {
    if (projectId != null) {
      return _fetchProjectShared(projectId);
    }

    final projects = await _loadProjects();
    final results = <Map<String, dynamic>>[];
    final batches = await Future.wait(
      projects.map((project) async {
        final pid = _int(project['id']);
        if (pid == null) return <Map<String, dynamic>>[];
        final r = await _fetchProjectShared(pid);
        if (r['success'] == true) {
          return (r['results'] as List? ?? [])
              .whereType<Map>()
              .map((row) => normalizeVaultEntry(Map<String, dynamic>.from(row)))
              .toList();
        }
        return <Map<String, dynamic>>[];
      }),
    );
    for (final batch in batches) {
      results.addAll(batch);
    }

    return {
      'success': true,
      'data': {'count': results.length, 'results': results},
      'count': results.length,
      'results': results,
    };
  }

  Future<Map<String, dynamic>> _fetchProjectShared(int projectId) async {
    final r = await _api.getVaultSharedWithMe(projectId: projectId);
    if (r['success'] == true) {
      final results = (r['results'] as List? ?? r['data']?['results'] as List? ?? [])
          .whereType<Map>()
          .map((e) => normalizeVaultEntry(Map<String, dynamic>.from(e)))
          .toList();
      return {
        'success': true,
        'data': {'count': results.length, 'results': results, 'project_id': projectId},
        'count': results.length,
        'results': results,
      };
    }
    final err = r['error']?.toString();
    if (isAccessesFieldError(err)) {
      return {
        'success': true,
        'data': {'count': 0, 'results': <dynamic>[], 'project_id': projectId},
        'count': 0,
        'results': <dynamic>[],
      };
    }
    return r;
  }

  Future<List<Map<String, dynamic>>> _loadProjects() async {
    final fromList = await _projectsFromListApi();
    if (fromList.isNotEmpty) return fromList;
    return _projectsFromVaultContext();
  }

  Future<List<Map<String, dynamic>>> _projectsFromListApi() async {
    final r = await _api.getProjects();
    if (r['success'] != true) return [];
    return (r['data'] as List? ?? [])
        .whereType<Map>()
        .map((p) => Map<String, dynamic>.from(p))
        .where((p) => p['is_archived'] != true)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _projectsFromVaultContext() async {
    final custR = await _api.getVaultContextCustomers();
    if (custR['success'] != true) return [];

    final customers = (custR['data'] as List? ?? []).whereType<Map>();
    final projects = <Map<String, dynamic>>[];

    for (final customer in customers) {
      final customerId = _int(customer['id']);
      if (customerId == null) continue;
      final customerName = customer['name']?.toString() ?? '';

      final projR = await _api.getVaultContextCustomerProjects(customerId);
      if (projR['success'] != true) continue;

      final data = Map<String, dynamic>.from(projR['data'] as Map? ?? {});
      final rows = (data['projects'] as List? ?? []).whereType<Map>();
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row);
        map['customer_id'] = customerId;
        map['customer_name'] = customerName;
        projects.add(map);
      }
    }
    return projects;
  }

  int? _int(dynamic v) {
    if (v is int) return v;
    return int.tryParse('$v');
  }
}
