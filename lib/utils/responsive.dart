import 'package:flutter/material.dart';

/// Shared breakpoints for phone / tablet / desktop layouts.
class Responsive {
  static const double mobileMax = 600;
  static const double tabletMax = 1024;

  static double widthOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isMobile(BuildContext context) => widthOf(context) < mobileMax;
  static bool isTablet(BuildContext context) {
    final w = widthOf(context);
    return w >= mobileMax && w < tabletMax;
  }

  static bool isDesktop(BuildContext context) => widthOf(context) >= tabletMax;

  /// Use full window width (no centered max-width column).
  static bool useFullWidth(BuildContext context) => isDesktop(context);

  /// Sidebar removed — always use top + bottom navigation.
  static bool useSideNav(BuildContext context) => false;

  static double pagePadding(BuildContext context) {
    final w = widthOf(context);
    if (w >= 1600) return 40;
    if (isDesktop(context)) return 28;
    if (isTablet(context)) return 24;
    return 16;
  }

  static double contentMaxWidth(BuildContext context) {
    final w = widthOf(context);
    if (w >= 1600) return 1280;
    if (w >= 1200) return 1120;
    if (isDesktop(context)) return 960;
    if (isTablet(context)) return 720;
    return double.infinity;
  }

  /// Full-bleed pages (chat, work board) may use more horizontal space.
  static double wideContentMaxWidth(BuildContext context) {
    final w = widthOf(context);
    if (w >= 1600) return 1480;
    if (w >= 1200) return 1320;
    return contentMaxWidth(context);
  }

  /// Space reserved above [AppBottomNavBar] when [Scaffold.extendBody] is true.
  ///
  /// Only the icon bar + chrome — system gesture inset is already consumed by
  /// [AppBottomNavBar]'s own SafeArea. Including it here doubles the gap.
  static double bottomNavInset(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 420;
    final navHeight = compact ? 56.0 : 62.0;
    const navChrome = 8.0;
    return navHeight + navChrome;
  }

  static int projectGridColumns(BuildContext context) {
    final w = widthOf(context);
    if (w >= 1600) return 4;
    if (w >= 1200) return 3;
    if (w >= 560) return 2;
    return 1;
  }

  static SliverGridDelegate projectGridDelegate(BuildContext context, {bool embedded = false}) {
    final cross = projectGridColumns(context);
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: cross,
      mainAxisSpacing: embedded ? 12 : 14,
      crossAxisSpacing: embedded ? 12 : 14,
      childAspectRatio: cross >= 3 ? 0.72 : (cross == 2 ? 0.82 : 1.05),
    );
  }

  /// Minimum card width so 2-column My Tasks fits typical desktop windows.
  static const double taskCardMinWidth = 248;

  /// Chat list | thread split (also used when window is moderately narrow).
  static const double chatSplitMinWidth = 560;

  static bool useChatSplit(BuildContext context) =>
      widthOf(context) >= chatSplitMinWidth;

  static double chatListPaneWidth(BuildContext context) {
    final w = widthOf(context);
    return (w * 0.28).clamp(220.0, 340.0);
  }

  /// My Task grid columns from available content width (resize-safe).
  /// Default desktop widths → 2 cols; narrow phone → 1; very wide → 3.
  static int taskGridColumnsForWidth(double availableWidth) {
    const gap = 10.0;
    if (availableWidth < taskCardMinWidth * 2 + gap) return 1;
    final cols = ((availableWidth + gap) / (taskCardMinWidth + gap)).floor();
    return cols.clamp(1, 3);
  }

  static int taskGridColumns(BuildContext context) {
    final pad = pagePadding(context);
    final available = widthOf(context) - (pad * 2);
    return taskGridColumnsForWidth(available);
  }

  static bool useTaskGrid(BuildContext context) => taskGridColumns(context) > 1;

  static SliverGridDelegate taskGridDelegate(BuildContext context) {
    final cross = taskGridColumns(context);
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: cross,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      mainAxisExtent: cross >= 4 ? 196 : (cross >= 3 ? 188 : 172),
    );
  }

  static double kanbanColumnWidth(BuildContext context) {
    final w = widthOf(context);
    if (w >= 1200) return 320;
    if (w >= 900) return 300;
    if (w >= 600) return 280;
    return 260;
  }

  static double timerFontSize(BuildContext context) {
    if (isDesktop(context)) return 56;
    if (isTablet(context)) return 48;
    return 40;
  }

  static Widget constrainContent(BuildContext context, Widget child, {double? maxWidth}) {
    if (useFullWidth(context) && maxWidth == null) {
      return child;
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? contentMaxWidth(context)),
        child: child,
      ),
    );
  }

  static Widget constrainWide(BuildContext context, Widget child) {
    if (useFullWidth(context)) return child;
    return constrainContent(context, child, maxWidth: wideContentMaxWidth(context));
  }
}
