import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_toast.dart';

/// Share a vault entry with company employees.
Future<void> showVaultShareSheet({
  required BuildContext context,
  required ApiService apiService,
  required int projectId,
  required int entryId,
  required String entryName,
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
    builder: (ctx) => _VaultShareSheet(
      apiService: apiService,
      projectId: projectId,
      entryId: entryId,
      entryName: entryName,
      onChanged: onChanged,
    ),
  );
}

class _VaultShareSheet extends StatefulWidget {
  final ApiService apiService;
  final int projectId;
  final int entryId;
  final String entryName;
  final VoidCallback? onChanged;

  const _VaultShareSheet({
    required this.apiService,
    required this.projectId,
    required this.entryId,
    required this.entryName,
    this.onChanged,
  });

  @override
  State<_VaultShareSheet> createState() => _VaultShareSheetState();
}

class _VaultShareSheetState extends State<_VaultShareSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _shares = [];
  final Set<int> _selectedUserIds = {};
  String _permission = 'view';
  bool _sharing = false;

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
    final shareR = await widget.apiService.getVaultShares(widget.projectId, widget.entryId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (empR['success'] != true) {
        _error = empR['error']?.toString() ?? 'Failed to load employees';
        return;
      }
      _employees = (empR['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _shares = shareR['success'] == true
          ? (shareR['data'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : [];
    });
  }

  Future<void> _shareSelected() async {
    if (_selectedUserIds.isEmpty) return;
    setState(() => _sharing = true);
    final r = await widget.apiService.shareVaultEntry(
      widget.projectId,
      widget.entryId,
      userIds: _selectedUserIds.toList(),
      permission: _permission,
    );
    if (!mounted) return;
    setState(() => _sharing = false);
    if (r['success'] == true) {
      _selectedUserIds.clear();
      widget.onChanged?.call();
      await _load();
      if (mounted) {
        AppToast.success(context, 'Shared successfully');
      }
    } else {
      AppToast.error(context, r['error']?.toString() ?? 'Share failed');
    }
  }

  Future<void> _removeShare(int shareId) async {
    final r = await widget.apiService.removeVaultShare(widget.projectId, widget.entryId, shareId);
    if (!mounted) return;
    if (r['success'] == true) {
      widget.onChanged?.call();
      await _load();
    } else {
      AppToast.error(context, r['error']?.toString() ?? 'Remove failed');
    }
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
      if (u['email'] != null) return u['email'].toString();
    }
    return e['name']?.toString() ?? e['email']?.toString() ?? 'Employee';
  }

  @override
  Widget build(BuildContext context) {
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
          Text(
            'Share "${widget.entryName}"',
            style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
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
              decoration: _deco('Permission'),
              items: const [
                DropdownMenuItem(value: 'view', child: Text('View only')),
                DropdownMenuItem(value: 'copy', child: Text('View & copy')),
                DropdownMenuItem(value: 'edit', child: Text('Edit')),
              ],
              onChanged: (v) => setState(() => _permission = v ?? 'view'),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.25),
              child: ListView(
                shrinkWrap: true,
                children: _employees.map((e) {
                  final uid = _employeeUserId(e);
                  if (uid == null) return const SizedBox.shrink();
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
              onPressed: _sharing || _selectedUserIds.isEmpty ? null : _shareSelected,
              child: _sharing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Share with selected'),
            ),
            if (_shares.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Current shares', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              const SizedBox(height: 6),
              ..._shares.map((s) {
                final id = s['id'] is int ? s['id'] as int : int.tryParse('${s['id']}') ?? 0;
                final name = s['shared_with_user_name']?.toString() ?? s['shared_with_email']?.toString() ?? 'User';
                final perm = s['permission']?.toString() ?? 'view';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                  subtitle: Text(perm, style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.8), fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_remove_outlined, size: 18, color: AppTheme.danger),
                    onPressed: id > 0 ? () => _removeShare(id) : null,
                  ),
                );
              }),
            ],
          ],
        ],
      ),
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
}

/// Vault activity log (project-wide or single entry).
Future<void> showVaultActivitySheet({
  required BuildContext context,
  required ApiService apiService,
  required int projectId,
  int? entryId,
  String? entryName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface2,
    barrierColor: AppTheme.modalBarrierColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _VaultActivitySheet(
      apiService: apiService,
      projectId: projectId,
      entryId: entryId,
      entryName: entryName,
    ),
  );
}

class _VaultActivitySheet extends StatefulWidget {
  final ApiService apiService;
  final int projectId;
  final int? entryId;
  final String? entryName;

  const _VaultActivitySheet({
    required this.apiService,
    required this.projectId,
    this.entryId,
    this.entryName,
  });

  @override
  State<_VaultActivitySheet> createState() => _VaultActivitySheetState();
}

class _VaultActivitySheetState extends State<_VaultActivitySheet> {
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
        _items = [];
      });
    } else {
      setState(() => _loadingMore = true);
    }
    final r = widget.entryId != null
        ? await widget.apiService.getVaultEntryActivity(widget.projectId, widget.entryId!, page: _page)
        : await widget.apiService.getVaultActivity(widget.projectId, page: _page);
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = r['error']?.toString() ?? 'Failed to load activity';
      });
      return;
    }
    final batch = (r['data'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    setState(() {
      _loading = false;
      _loadingMore = false;
      _items.addAll(batch);
      _hasMore = r['next'] != null && batch.isNotEmpty;
      if (batch.isNotEmpty) _page++;
    });
  }

  String _fmt(dynamic iso) {
    try {
      return DateFormat('dd MMM yyyy HH:mm').format(DateTime.parse(iso.toString()).toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.7;
    final title = widget.entryId != null
        ? 'Activity — ${widget.entryName ?? 'Entry'}'
        : 'Vault activity';

    return SizedBox(
      height: maxH,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
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
            Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBright))
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.danger)))
                      : _items.isEmpty
                          ? const Center(child: Text('No activity yet', style: TextStyle(color: AppTheme.textMuted)))
                          : ListView.builder(
                              itemCount: _items.length + (_hasMore ? 1 : 0),
                              itemBuilder: (ctx, i) {
                                if (i == _items.length) {
                                  return TextButton(
                                    onPressed: _loadingMore ? null : () => _load(),
                                    child: _loadingMore
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Text('Load more'),
                                  );
                                }
                                final a = _items[i];
                                final summary = a['summary']?.toString() ?? a['description']?.toString() ?? a['action']?.toString() ?? 'Activity';
                                final user = a['user_name']?.toString() ?? 'User';
                                final ts = _fmt(a['timestamp']);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: AppTheme.glassPanel(borderRadius: 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(summary, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$user · $ts',
                                          style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.75), fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
