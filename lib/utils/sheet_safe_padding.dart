import 'package:flutter/material.dart';

/// Extra lift above Android 3-button / gesture nav so sheet actions stay tappable.
const kSheetNavClearance = 12.0;

/// Bottom padding for modal sheets / save buttons: keyboard + system nav + clearance.
double sheetBottomSafePadding(BuildContext context, {double extra = kSheetNavClearance}) {
  final mq = MediaQuery.of(context);
  return mq.viewInsets.bottom + mq.viewPadding.bottom + extra;
}
