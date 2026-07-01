import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/project_vault_tab.dart';
import '../widgets/tool_page_scaffold.dart';

/// Browse vault by customer → project, then open project credentials.
class VaultHubPage extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback? onLogout;

  const VaultHubPage({
    super.key,
    required this.apiService,
    this.onLogout,
  });

  @override
  State<VaultHubPage> createState() => _VaultHubPageState();
}

class _VaultHubPageState extends State<VaultHubPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _customers = [];
  Map<String, dynamic>? _selectedCustomer;
  List<Map<String, dynamic>> _customerProjects = [];
  bool _loadingProjects = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedCustomer = null;
      _customerProjects = [];
    });
    final r = await widget.apiService.getVaultContextCustomers();
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() {
        _loading = false;
        _error = r['error']?.toString() ?? 'Failed to load customers';
      });
      return;
    }
    setState(() {
      _customers = (r['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _loading = false;
    });
  }

  Future<void> _selectCustomer(Map<String, dynamic> customer) async {
    final id = customer['id'] is int ? customer['id'] as int : int.tryParse('${customer['id']}');
    if (id == null) return;
    setState(() {
      _selectedCustomer = customer;
      _loadingProjects = true;
      _customerProjects = [];
    });
    final r = await widget.apiService.getVaultContextCustomerProjects(id);
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() {
        _loadingProjects = false;
        _error = r['error']?.toString() ?? 'Failed to load projects';
      });
      return;
    }
    final data = r['data'] as Map? ?? {};
    setState(() {
      _loadingProjects = false;
      _customerProjects = (data['projects'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    });
  }

  void _backToCustomers() {
    setState(() {
      _selectedCustomer = null;
      _customerProjects = [];
      _error = null;
    });
  }

  void _openVault(Map<String, dynamic> project) {
    final id = project['id'];
    final projectId = id is int ? id : int.tryParse('$id');
    if (projectId == null) return;
    final name = project['name']?.toString() ?? 'Project';
    final customerName = _selectedCustomer?['name']?.toString() ?? '';

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          body: Container(
            decoration: AppTheme.screenGradient(),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textMuted),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Vault',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                customerName.isNotEmpty ? '$name · $customerName' : name,
                                style: TextStyle(
                                  color: AppTheme.textMuted.withValues(alpha: 0.85),
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ProjectVaultTab(
                      apiService: widget.apiService,
                      projectId: projectId,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _listTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.glassPanel(borderRadius: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppTheme.primaryBright, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: AppTheme.textMuted.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ToolPageScaffold(
      title: 'Vault',
      subtitle: _selectedCustomer == null
          ? 'Select a customer to browse project credentials'
          : 'Projects for ${_selectedCustomer!['name']}',
      onLogout: widget.onLogout,
      child: _loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: AppTheme.primaryBright),
              ),
            )
          : _error != null && _customers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _loadCustomers, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _selectedCustomer == null
                  ? _customers.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(24),
                          decoration: AppTheme.glassPanel(borderRadius: 16),
                          child: const Text(
                            'No customers found. Vault entries live inside each project.',
                            style: TextStyle(color: AppTheme.textMuted, height: 1.4),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                              ),
                            ..._customers.map((c) => _listTile(
                                  icon: Icons.business_outlined,
                                  title: c['name']?.toString() ?? 'Customer',
                                  subtitle: c['email']?.toString(),
                                  onTap: () => _selectCustomer(c),
                                )),
                          ],
                        )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _backToCustomers,
                            icon: const Icon(Icons.arrow_back_rounded, size: 18),
                            label: const Text('All customers'),
                          ),
                        ),
                        if (_loadingProjects)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator(color: AppTheme.primaryBright)),
                          )
                        else if (_customerProjects.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: AppTheme.glassPanel(borderRadius: 16),
                            child: const Text(
                              'No active projects for this customer.',
                              style: TextStyle(color: AppTheme.textMuted, height: 1.4),
                            ),
                          )
                        else
                          ..._customerProjects.map((p) => _listTile(
                                icon: Icons.lock_outline_rounded,
                                title: p['name']?.toString() ?? 'Project',
                                subtitle: p['status']?.toString(),
                                onTap: () => _openVault(p),
                              )),
                      ],
                    ),
    );
  }
}
