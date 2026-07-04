import 'package:flutter/material.dart';

import '../utils/app_toast.dart';

/// Multi-select assignee picker (same flow as web `openKanbanAssigneePicker`).
Future<List<int>?> showKanbanAssigneePicker({
  required BuildContext context,
  required List<dynamic> employees,
  required List<int> selectedIds,
  bool requireAtLeastOne = true,
}) async {
  final selected = {...selectedIds};
  return showModalBottomSheet<List<int>>(
    context: context,
    backgroundColor: const Color(0xFF1e293b),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Assign people',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, color: Colors.white54),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select one or more team members',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final e in employees)
                        _employeeTile(
                          e,
                          selected,
                          (id, on) {
                            setLocal(() {
                              if (on) {
                                selected.add(id);
                              } else {
                                selected.remove(id);
                              }
                            });
                          },
                        ),
                      if (employees.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No assignable people on this project',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    if (requireAtLeastOne && selected.isEmpty) {
                      AppToast.warning(ctx, 'Select at least one assignee');
                      return;
                    }
                    Navigator.pop(ctx, selected.toList()..sort());
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save assignees'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _employeeTile(
  dynamic e,
  Set<int> selected,
  void Function(int id, bool on) onToggle,
) {
  final idRaw = e['user_id'] ?? e['id'];
  final id = idRaw is int ? idRaw : int.tryParse('$idRaw');
  if (id == null) return const SizedBox.shrink();
  final name = (e['full_name'] ?? e['username'] ?? e['name'] ?? 'User').toString();
  final role = (e['designation'] ?? e['role'] ?? '').toString();
  final checked = selected.contains(id);
  return CheckboxListTile(
    value: checked,
    onChanged: (v) => onToggle(id, v == true),
    activeColor: const Color(0xFF8B5CF6),
    checkColor: Colors.white,
    title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
    subtitle: role.isNotEmpty
        ? Text(role, style: const TextStyle(color: Colors.white38, fontSize: 12))
        : null,
    secondary: CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFF334155),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    ),
    controlAffinity: ListTileControlAffinity.trailing,
  );
}
