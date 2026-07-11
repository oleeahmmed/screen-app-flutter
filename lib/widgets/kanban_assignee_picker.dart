import 'package:flutter/material.dart';

import '../utils/app_toast.dart';
import '../utils/task_helpers.dart';

/// Multi-select assignee picker (same flow as web `openKanbanAssigneePicker`).
Future<List<int>?> showKanbanAssigneePicker({
  required BuildContext context,
  required List<dynamic> employees,
  required List<int> selectedIds,
  bool requireAtLeastOne = true,
}) async {
  final people = normalizeProjectEmployeesList(employees);
  return showModalBottomSheet<List<int>>(
    context: context,
    backgroundColor: const Color(0xFF1e293b),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _KanbanAssigneePickerSheet(
      employees: people,
      initialSelected: selectedIds,
      requireAtLeastOne: requireAtLeastOne,
    ),
  );
}

class _KanbanAssigneePickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final List<int> initialSelected;
  final bool requireAtLeastOne;

  const _KanbanAssigneePickerSheet({
    required this.employees,
    required this.initialSelected,
    required this.requireAtLeastOne,
  });

  @override
  State<_KanbanAssigneePickerSheet> createState() => _KanbanAssigneePickerSheetState();
}

class _KanbanAssigneePickerSheetState extends State<_KanbanAssigneePickerSheet> {
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelected};
  }

  void _toggle(int id, bool on) {
    setState(() {
      if (on) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Assign people (${_selected.length} selected)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
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
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: widget.employees.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No assignable people on this project',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.employees.length,
                    itemBuilder: (context, i) => _employeeTile(
                      widget.employees[i],
                      _selected,
                      _toggle,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (widget.requireAtLeastOne && _selected.isEmpty) {
                AppToast.warning(context, 'Select at least one assignee');
                return;
              }
              Navigator.pop(context, _selected.toList()..sort());
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
  }
}

Widget _employeeTile(
  Map<String, dynamic> e,
  Set<int> selected,
  void Function(int id, bool on) onToggle,
) {
  final id = employeeUserIdFrom(e);
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
