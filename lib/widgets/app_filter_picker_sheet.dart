// app_filter_picker_sheet.dart — pick Windows apps for foreground window capture

import 'package:flutter/material.dart';

import '../services/windows_app_capture.dart';
import '../theme/app_theme.dart';

class AppFilterPickerSheet extends StatefulWidget {
  final List<WindowsAppInfo> initialSelectedApps;

  const AppFilterPickerSheet({
    super.key,
    required this.initialSelectedApps,
  });

  static Future<List<WindowsAppInfo>?> show(
    BuildContext context, {
    List<WindowsAppInfo> initialSelectedApps = const [],
    @Deprecated('Use initialSelectedApps') List<String>? initialSelectedExes,
  }) {
    var seed = initialSelectedApps;
    if (seed.isEmpty && initialSelectedExes != null && initialSelectedExes.isNotEmpty) {
      seed = initialSelectedExes
          .map((e) => WindowsAppInfo(name: e, exe: e, title: ''))
          .toList();
    }
    return showModalBottomSheet<List<WindowsAppInfo>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AppFilterPickerSheet(initialSelectedApps: seed),
    );
  }

  @override
  State<AppFilterPickerSheet> createState() => _AppFilterPickerSheetState();
}

class _AppFilterPickerSheetState extends State<AppFilterPickerSheet> {
  final _selected = <String>{};
  final _savedByExe = <String, WindowsAppInfo>{};
  final _runningKeys = <String>{};
  List<WindowsAppInfo> _apps = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final a in widget.initialSelectedApps) {
      final key = a.exe.toLowerCase();
      if (key.isEmpty) continue;
      _selected.add(key);
      _savedByExe[key] = a;
    }
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apps = await WindowsAppCapture.listRunningApps();
      if (!mounted) return;
      final runningKeys = apps.map((a) => a.exe.toLowerCase()).toSet();
      final offline = _savedByExe.entries
          .where((e) => !runningKeys.contains(e.key))
          .map((e) => e.value)
          .toList();
      setState(() {
        _runningKeys
          ..clear()
          ..addAll(runningKeys);
        _apps = [...offline, ...apps];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toggle(WindowsAppInfo app) {
    setState(() {
      final key = app.exe.toLowerCase();
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
        _savedByExe[key] = app;
      }
    });
  }

  List<WindowsAppInfo> _buildSelection() {
    final byExe = <String, WindowsAppInfo>{
      ..._savedByExe,
      for (final a in _apps) a.exe.toLowerCase(): a,
    };
    final out = <WindowsAppInfo>[];
    for (final key in _selected) {
      final app = byExe[key];
      if (app != null && app.exe.trim().isNotEmpty) out.add(app);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        decoration: AppTheme.loginShell().copyWith(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textMuted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select Apps',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : _loadApps,
                    icon: const Icon(Icons.refresh_rounded, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'While clocked in, only these apps are captured when they are on top.',
                style: TextStyle(
                  color: AppTheme.textMuted.withValues(alpha: 0.9),
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(_error!, style: const TextStyle(color: AppTheme.danger)),
              )
            else if (_apps.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'No visible app windows found. Open the apps you want, then tap Refresh.',
                  style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.9)),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _apps.length,
                  itemBuilder: (context, index) {
                    final app = _apps[index];
                    final key = app.exe.toLowerCase();
                    final checked = _selected.contains(key);
                    final offline = !_runningKeys.contains(key);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (_) => _toggle(app),
                      activeColor: AppTheme.accent,
                      title: Text(
                        app.name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        offline ? '${app.exe} · not running now' : app.exe,
                        style: TextStyle(
                          color: AppTheme.textMuted.withValues(alpha: 0.85),
                          fontSize: 11,
                        ),
                      ),
                      secondary: Icon(
                        offline ? Icons.desktop_access_disabled_rounded : Icons.apps_rounded,
                        color: offline ? AppTheme.textMuted : AppTheme.accent,
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _buildSelection()),
                      child: Text('Save (${_selected.length})'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
