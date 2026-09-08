import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared surfaces for Reports hub + attendance pages (matches Home / closing report).
class ReportUi {
  static const titleStyle = TextStyle(
    color: AppTheme.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.none,
  );

  static const mutedStyle = TextStyle(
    color: AppTheme.textMuted,
    fontSize: 12,
    decoration: TextDecoration.none,
  );

  static BoxDecoration card({double radius = 16}) =>
      AppTheme.taskCardDecoration(borderRadius: radius);

  static BoxDecoration inset({double radius = 12}) =>
      AppTheme.homeGlossInsetDecoration(borderRadius: radius);

  static Widget glossCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    double radius = 16,
  }) {
    return AppTheme.homeGlossCard(
      padding: padding,
      borderRadius: radius,
      child: child,
    );
  }

  static Widget iconBox({
    required IconData icon,
    Color color = AppTheme.primaryBright,
    double size = 40,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }

  static ButtonStyle primaryButton({EdgeInsetsGeometry? padding}) {
    return FilledButton.styleFrom(
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      disabledForegroundColor: AppTheme.textPrimary.withValues(alpha: 0.5),
      padding: padding ?? const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
    );
  }

  static Widget sectionLabel(String title, {int? count}) {
    return Row(
      children: [
        Text(title, style: titleStyle),
        if (count != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: inset(radius: 8),
            child: Text(
              '$count',
              style: mutedStyle.copyWith(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }

  static Widget listTile({
    required Widget leading,
    required Widget title,
    Widget? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: card(radius: 14),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                if (subtitle != null) ...[const SizedBox(height: 2), subtitle],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );

    if (onTap == null) {
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: child);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: child,
        ),
      ),
    );
  }

  /// Glossy, horizontally scrollable data table for mobile reports.
  static Widget dataTable({
    required List<ReportTableColumn> columns,
    required List<ReportTableRow> rows,
    String? emptyMessage,
    bool compact = true,
    double columnGap = 6,
  }) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: inset(),
        child: Text(
          emptyMessage ?? 'No records',
          style: mutedStyle,
          textAlign: TextAlign.center,
        ),
      );
    }

    final rowPadV = compact ? 10.0 : 12.0;
    final rowPadH = compact ? 8.0 : 10.0;
    final headerStyle = TextStyle(
      color: AppTheme.textMuted.withValues(alpha: 0.95),
      fontSize: compact ? 9.5 : 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
      decoration: TextDecoration.none,
    );
    final cellStyle = TextStyle(
      color: AppTheme.textPrimary,
      fontSize: compact ? 11 : 11.5,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.none,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final mutedCellStyle = cellStyle.copyWith(
      color: AppTheme.textMuted,
      fontWeight: FontWeight.w500,
      fontSize: compact ? 10.5 : 11,
    );

    double totalFixedWidth() {
      final cols = columns.fold<double>(0, (sum, c) => sum + c.width);
      final gaps = (columns.length - 1) * columnGap;
      return cols + gaps + rowPadH * 2;
    }

    Widget buildCell(ReportTableCell cell, ReportTableColumn column, {bool isHeader = false, bool flexible = false}) {
      final align = column.align;
      final baseStyle = isHeader
          ? headerStyle
          : (cell.style ?? (cell.muted ? mutedCellStyle : cellStyle));
      final content = cell.child ??
          Text(
            cell.text,
            style: baseStyle.copyWith(color: cell.color ?? baseStyle.color),
            textAlign: align,
            maxLines: cell.maxLines,
            overflow: TextOverflow.ellipsis,
          );
      final aligned = Align(
        alignment: _alignmentFor(align),
        widthFactor: flexible ? 1 : null,
        child: cell.child != null
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: _alignmentFor(align),
                child: content,
              )
            : content,
      );
      if (flexible) {
        return Expanded(
          flex: column.flex,
          child: aligned,
        );
      }
      return SizedBox(width: column.width, child: aligned);
    }

    Widget buildRow(List<ReportTableCell> cells, {bool isHeader = false, bool flexible = false, VoidCallback? onTap, int? stripeIndex}) {
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < columns.length; i++) ...[
            if (i > 0) SizedBox(width: columnGap),
            buildCell(cells[i], columns[i], isHeader: isHeader, flexible: flexible),
          ],
        ],
      );

      if (isHeader) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: rowPadH, vertical: rowPadV - 1),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: row,
        );
      }

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: rowPadH, vertical: rowPadV),
            decoration: BoxDecoration(
              color: stripeIndex != null && stripeIndex.isEven
                  ? Colors.white.withValues(alpha: 0.02)
                  : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: stripeIndex == rows.length - 1 ? 0 : 0.05),
                ),
              ),
            ),
            child: row,
          ),
        ),
      );
    }

    return Container(
      decoration: card(radius: 14),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fixedWidth = totalFixedWidth();
          final needsScroll = fixedWidth > constraints.maxWidth + 0.5;
          final flexible = !needsScroll;

          Widget tableBody = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildRow(
                columns.map((c) => ReportTableCell(text: c.label)).toList(),
                isHeader: true,
                flexible: flexible,
              ),
              for (var r = 0; r < rows.length; r++)
                buildRow(
                  rows[r].cells,
                  flexible: flexible,
                  onTap: rows[r].onTap,
                  stripeIndex: r,
                ),
            ],
          );

          if (!needsScroll) return tableBody;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              width: fixedWidth,
              child: tableBody,
            ),
          );
        },
      ),
    );
  }

  static Alignment _alignmentFor(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      default:
        return Alignment.centerLeft;
    }
  }

  static Widget statusChip(String label, Color color, {bool compact = true}) {
    return Container(
      constraints: BoxConstraints(maxWidth: compact ? 64 : 72),
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 3 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: compact ? 9 : 9.5,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class ReportTableColumn {
  final String label;
  final double width;
  final int flex;
  final TextAlign align;

  const ReportTableColumn({
    required this.label,
    required this.width,
    this.flex = 1,
    this.align = TextAlign.left,
  });
}

class ReportTableCell {
  final String text;
  final Widget? child;
  final TextStyle? style;
  final Color? color;
  final bool muted;
  final int maxLines;

  const ReportTableCell({
    this.text = '',
    this.child,
    this.style,
    this.color,
    this.muted = false,
    this.maxLines = 2,
  });
}

class ReportTableRow {
  final List<ReportTableCell> cells;
  final VoidCallback? onTap;

  const ReportTableRow({required this.cells, this.onTap});
}
