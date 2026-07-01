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
