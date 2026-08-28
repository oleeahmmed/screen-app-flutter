import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_toast.dart';

/// Admin: grant / revoke category-level vault access (view or edit).
Future<void> showVaultCategoryAccessSheet({
  required BuildContext context,
  required ApiService apiService,
  required int projectId,
  required int categoryId,
  required String categoryName,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface2,
    barrierColor: AppTheme.modalBarrierColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _VaultCategoryAccessSheet(
      apiService: apiService,
      projectId: projectId,
      categoryId: categoryId,
      categoryName: categoryName,
      onChanged: onChanged,
    ),
  );
}

class _VaultCategoryAccessSheet extends StatefulWidget {
  final ApiService apiService;
  final int projectId;
  final int categoryId;
  final String categoryName;
  final VoidCallback? onChanged;

  const _VaultCategoryAccessSheet({
    required this.apiService,
    required this.projectId,
    required this.categoryId,
    required this.categoryName,
    this.onChanged,
  });

  @override
  State<_VaultCategoryAccessSheet> createState() => _VaultCategoryAccessSheetState();
}

class _VaultCategoryAccessSheetState extends State<_VaultCategoryAccessSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _accesses = [];
  final Set<int> _selectedUserIds = {};
  String _permission = 'view';
  bool _saving = false;

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
    final empR = await widget.apiService.getCompanyEmployees();
    final accR = await widget.apiService.getVaultCategoryAccess(widget.projectId, widget.categoryId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (empR['success'] != true) {
        _error = empR['error']?.toString() ?? 'Failed to load employees';
        return;
      }
      if (accR['success'] != true) {
        _error = accR['error']?.toString() ?? 'Failed to load access';
        return;
      }
      _employees = (empR['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _accesses = (accR['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    });
  }

  int? _employeeUserId(Map<String, dynamic> e) {
    final u = e['user'];
    if (u is Map && u['id'] != null) return u['id'] is int ? u['id'] as int : int.tryParse('${u['id']}');
    if (e['user_id'] != null) return e['user_id'] is int ? e['user_id'] as int : int.tryParse('${e['user_id']}');
    if (e['id'] != null) return e['id'] is int ? e['id'] as int : int.tryParse('${e['id']}');
    return null;
  }

  String _employeeLabel(Map<String, dynamic> e) {
    final u = e['user'];
    if (u is Map) {
      final name = u['full_name'] ?? u['name'] ?? '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
      if (name.toString().trim().isNotEmpty) return name.toString();
      if (u['username'] != null) return u['username'].toString();
    }
    return e['name']?.toString() ?? e['email']?.toString() ?? 'Employee';
  }

  Set<int> get _grantedUserIds {
    final ids = <int>{};
    for (final a in _accesses) {
      final u = a['user'];
      if (u is Map && u['id'] != null) {
        final id = u['id'] is int ? u['id'] as int : int.tryParse('${u['id']}');
        if (id != null) ids.add(id);
      }
    }
    return ids;
  }

  Future<void> _grantSelected() async {
    if (_selectedUserIds.isEmpty) return;
    setState(() => _saving = true);
    final r = await widget.apiService.grantVaultCategoryAccess(
      widget.projectId,
      widget.categoryId,
      userIds: _selectedUserIds.toList(),
      permission: _permission,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      _selectedUserIds.clear();
      widget.onChanged?.call();
      await _load();
      if (mounted) AppToast.success(context, 'Access granted');
    } else {
      AppToast.error(context, r['error']?.toString() ?? 'Grant failed');
    }
  }

  Future<void> _setPermission(Map<String, dynamic> access, String permission) async {
    final u = access['user'];
    final userId = u is Map
        ? (u['id'] is int ? u['id'] as int : int.tryParse('${u['id']}'))
        : null;
    if (userId == null) return;
    final r = await widget.apiService.updateVaultCategoryAccess(
      widget.projectId,
      widget.categoryId,
      userId,
      permission: permission,
    );
    if (!mounted) return;
    if (r['success'] == true) {
      widget.onChanged?.call();
      await _load();
    } else {
      AppToast.error(context, r['error']?.toString() ?? 'Update failed');
    }
  }

  Future<void> _revoke(Map<String, dynamic> access) async {
    final u = access['user'];
    final userId = u is Map
        ? (u['id'] is int ? u['id'] as int : int.tryParse('${u['id']}'))
        : null;
    if (userId == null) return;
    final r = await widget.apiService.revokeVaultCategoryAccess(
      widget.projectId,
      widget.categoryId,
      userId,
    );
    if (!mounted) return;
    if (r['success'] == true) {
      widget.onChanged?.call();
      await _load();
      if (mounted) AppToast.success(context, 'Access removed');
    } else {
      AppToast.error(context, r['error']?.toString() ?? 'Remove failed');
    }
  }

  String _accessUserName(Map<String, dynamic> a) {
    final u = a['user'];
    if (u is Map) {
      return (u['name'] ?? u['full_name'] ?? u['username'] ?? 'User').toString();
    }
    return 'User';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final granted = _grantedUserIds;
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
          const Text(
            'Category access',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 4),
          Text(
            widget.categoryName,
            style: TextStyle(
              color: AppTheme.featureVault.withValues(alpha: 0.95),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Users only see entries in categories you grant.',
            style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: AppTheme.primaryBright)),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppTheme.danger))
          else ...[
            DropdownButtonFormField<String>(
              value: _permission,
              dropdownColor: AppTheme.surface2,
              decoration: InputDecoration(
                labelText: 'Permission',
                labelStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: const [
                DropdownMenuItem(value: 'view', child: Text('View only')),
                DropdownMenuItem(value: 'edit', child: Text('View & edit entries')),
              ],
              onChanged: (v) => setState(() => _permission = v ?? 'view'),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.22),
              child: ListView(
                shrinkWrap: true,
                children: _employees.map((e) {
                  final uid = _employeeUserId(e);
                  if (uid == null || granted.contains(uid)) return const SizedBox.shrink();
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(_employeeLabel(e), style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                    value: _selectedUserIds.contains(uid),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedUserIds.add(uid);
                        } else {
                          _selectedUserIds.remove(uid);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving || _selectedUserIds.isEmpty ? null : _grantSelected,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.featureVault),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Grant access'),
            ),
            if (_accesses.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'People with access',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.28),
                child: ListView(
                  shrinkWrap: true,
                  children: _accesses.map((a) {
                    final perm = (a['permission'] ?? 'view').toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: AppTheme.featureVault.withValues(alpha: 0.25),
                            child: Text(
                              _accessUserName(a).isNotEmpty ? _accessUserName(a)[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _accessUserName(a),
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  perm == 'edit' ? 'Can edit entries' : 'View only',
                                  style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.85), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            color: AppTheme.surface2,
                            icon: const Icon(Icons.more_horiz, color: AppTheme.textMuted, size: 18),
                            onSelected: (v) {
                              if (v == 'view' || v == 'edit') _setPermission(a, v);
                              if (v == 'revoke') _revoke(a);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'view', child: Text('Set view')),
                              PopupMenuItem(value: 'edit', child: Text('Set edit')),
                              PopupMenuItem(
                                value: 'revoke',
                                child: Text('Remove', style: TextStyle(color: AppTheme.danger)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
