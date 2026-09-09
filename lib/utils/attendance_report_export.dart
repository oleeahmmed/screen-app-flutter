import 'dart:convert' show utf8;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// CSV export for monthly attendance (single employee or company summary).
class AttendanceReportExport {
  static String _escape(String value) {
    final v = value.replaceAll('\r', ' ').replaceAll('\n', ' ');
    if (v.contains(',') || v.contains('"')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  static String _dur(dynamic block) {
    if (block is Map) {
      final f = block['formatted']?.toString();
      if (f != null && f.isNotEmpty) return f;
    }
    return '';
  }

  static String _timeOnly(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return DateFormat('HH:mm').format(dt.toLocal());
  }

  static String _statusLabel(String status, {bool late = false}) {
    switch (status) {
      case 'present':
        return late ? 'Late' : 'Present';
      case 'absent':
        return 'Absent';
      case 'weekly_off':
        return 'Weekly off';
      case 'holiday':
        return 'Holiday';
      case 'leave':
        return 'Leave';
      case 'future':
        return 'Future';
      default:
        return status;
    }
  }

  static List<String> _companyCsv(Map<String, dynamic> report) {
    final period = report['period'] is Map ? Map<String, dynamic>.from(report['period'] as Map) : <String, dynamic>{};
    final from = period['date_from']?.toString() ?? '';
    final to = period['date_to']?.toString() ?? '';
    final company = report['company'] is Map ? Map<String, dynamic>.from(report['company'] as Map) : <String, dynamic>{};
    final lines = <String>[
      'Monthly Attendance Summary',
      'Company,${_escape(company['name']?.toString() ?? '')}',
      'Period,$from to $to',
      '',
      'Employee,Present,Absent,Leave,Late,Net Work',
    ];

    for (final raw in report['employees'] as List? ?? const []) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final emp = row['employee'] is Map ? Map<String, dynamic>.from(row['employee'] as Map) : <String, dynamic>{};
      final summary = row['summary'] is Map ? Map<String, dynamic>.from(row['summary'] as Map) : <String, dynamic>{};
      lines.add([
        _escape(emp['full_name']?.toString() ?? ''),
        '${summary['present_days'] ?? 0}',
        '${summary['absent_days'] ?? 0}',
        '${summary['leave_days'] ?? 0}',
        '${summary['late_days'] ?? 0}',
        _escape(_dur(summary['total_net_duration'])),
      ].join(','));
    }

    final totals = report['totals'] is Map ? Map<String, dynamic>.from(report['totals'] as Map) : <String, dynamic>{};
    lines.add('');
    lines.add([
      'TOTAL',
      '${totals['present_days'] ?? 0}',
      '${totals['absent_days'] ?? 0}',
      '${totals['leave_days'] ?? 0}',
      '${totals['late_days'] ?? 0}',
      _escape(_dur(totals['total_net_duration'])),
    ].join(','));
    return lines;
  }

  static List<String> _employeeCsv(Map<String, dynamic> report) {
    final period = report['period'] is Map ? Map<String, dynamic>.from(report['period'] as Map) : <String, dynamic>{};
    final from = period['date_from']?.toString() ?? '';
    final to = period['date_to']?.toString() ?? '';
    final emp = report['employee'] is Map ? Map<String, dynamic>.from(report['employee'] as Map) : <String, dynamic>{};
    final summary = report['summary'] is Map ? Map<String, dynamic>.from(report['summary'] as Map) : <String, dynamic>{};
    final lines = <String>[
      'Monthly Attendance Report',
      'Employee,${_escape(emp['full_name']?.toString() ?? '')}',
      'Period,$from to $to',
      '',
      'Date,Weekday,Check In,Check Out,Break,Net,Status',
    ];

    for (final raw in report['days'] as List? ?? const []) {
      if (raw is! Map) continue;
      final d = Map<String, dynamic>.from(raw);
      final dateStr = d['date']?.toString() ?? '';
      final parsed = DateTime.tryParse(dateStr);
      final status = d['status']?.toString() ?? '';
      final showTimes = status == 'present' || status == 'absent';
      lines.add([
        dateStr,
        parsed != null ? DateFormat('EEE').format(parsed) : '',
        showTimes ? _timeOnly(d['first_check_in']?.toString()) : '',
        showTimes ? _timeOnly(d['last_check_out']?.toString()) : '',
        showTimes ? _dur(d['break_duration']) : '',
        showTimes ? _dur(d['net_duration']) : '',
        _escape(_statusLabel(status, late: d['late'] == true)),
      ].join(','));
    }

    lines.add('');
    lines.add('Summary,Value');
    lines.add('Present,${summary['present_days'] ?? 0}');
    lines.add('Absent,${summary['absent_days'] ?? 0}');
    lines.add('Leave,${summary['leave_days'] ?? 0}');
    lines.add('Late,${summary['late_days'] ?? 0}');
    lines.add('Total net work,${_escape(_dur(summary['total_net_duration']))}');
    return lines;
  }

  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  static Future<String> exportMonthlyReport(Map<String, dynamic> report) async {
    final scope = report['scope']?.toString() ?? 'employee';
    final lines = scope == 'company' ? _companyCsv(report) : _employeeCsv(report);
    final period = report['period'] is Map ? Map<String, dynamic>.from(report['period'] as Map) : <String, dynamic>{};
    final from = period['date_from']?.toString() ?? 'from';
    final to = period['date_to']?.toString() ?? 'to';
    final suffix = scope == 'company' ? 'company_summary' : 'employee';
    final fileName = 'attendance_${suffix}_${from}_$to.csv'.replaceAll(':', '-');
    final csv = '${lines.join('\n')}\n';
    final bytes = utf8.encode(csv);

    if (_isMobile) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      final xFile = XFile(file.path, mimeType: 'text/csv', name: fileName);
      await Share.shareXFiles(
        [xFile],
        subject: 'Monthly attendance report',
        text: 'Attendance report ($from to $to)',
      );
      return file.path;
    }

    if (_isDesktop) {
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save attendance report',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: bytes,
      );
      if (savedPath == null || savedPath.isEmpty) {
        throw Exception('Save cancelled');
      }
      final openResult = await OpenFilex.open(savedPath);
      if (openResult.type != ResultType.done) {
        return savedPath;
      }
      return savedPath;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    final openResult = await OpenFilex.open(file.path);
    if (openResult.type != ResultType.done) {
      throw Exception(openResult.message.isNotEmpty ? openResult.message : 'Could not open exported file');
    }
    return file.path;
  }
}
