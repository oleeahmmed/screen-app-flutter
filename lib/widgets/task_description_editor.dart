import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import '../theme/app_theme.dart';
import '../utils/task_helpers.dart';

/// WYSIWYG description editor (Flutter Quill) — saves HTML for web compatibility.
class TaskDescriptionEditor extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String>? onChanged;
  final double minHeight;

  const TaskDescriptionEditor({
    super.key,
    this.initialValue = '',
    this.onChanged,
    this.minHeight = 180,
  });

  @override
  State<TaskDescriptionEditor> createState() => _TaskDescriptionEditorState();
}

class _TaskDescriptionEditorState extends State<TaskDescriptionEditor> {
  late QuillController _controller;
  late final FocusNode _focusNode;
  bool _emitting = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _controller = QuillController(
      document: documentFromDescription(widget.initialValue),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _controller.addListener(_onDocChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onDocChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onDocChanged() {
    if (_emitting) return;
    _emitting = true;
    widget.onChanged?.call(descriptionToHtml(_controller));
    _emitting = false;
  }

  @override
  Widget build(BuildContext context) {
    final iconTheme = QuillIconTheme(
      iconButtonSelectedData: IconButtonData(
        color: AppTheme.accent,
        style: IconButton.styleFrom(
          foregroundColor: AppTheme.accent,
          backgroundColor: AppTheme.accent.withValues(alpha: 0.18),
        ),
      ),
      iconButtonUnselectedData: IconButtonData(
        color: AppTheme.textMuted,
        disabledColor: AppTheme.textMuted.withValues(alpha: 0.35),
        style: IconButton.styleFrom(
          foregroundColor: AppTheme.textMuted,
          disabledForegroundColor: AppTheme.textMuted.withValues(alpha: 0.35),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black.withValues(alpha: 0.22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
            ),
            child: QuillSimpleToolbar(
              controller: _controller,
              config: QuillSimpleToolbarConfig(
                multiRowsDisplay: false,
                showDividers: true,
                sectionDividerColor: Colors.white.withValues(alpha: 0.12),
                showFontFamily: false,
                showFontSize: false,
                showSubscript: false,
                showSuperscript: false,
                showSmallButton: false,
                showInlineCode: true,
                showColorButton: false,
                showBackgroundColorButton: false,
                showClearFormat: true,
                showAlignmentButtons: false,
                showDirection: false,
                showSearchButton: false,
                showCodeBlock: true,
                showQuote: true,
                showIndent: true,
                showLink: true,
                showListNumbers: true,
                showListBullets: true,
                showListCheck: true,
                showHeaderStyle: true,
                showUndo: true,
                showRedo: true,
                buttonOptions: QuillSimpleToolbarButtonOptions(
                  base: QuillToolbarBaseButtonOptions(iconTheme: iconTheme),
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: widget.minHeight),
            child: QuillEditor.basic(
              controller: _controller,
              focusNode: _focusNode,
              config: QuillEditorConfig(
                scrollable: false,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                placeholder: 'Write a clear description…',
                customStyles: _darkStyles(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  DefaultStyles _darkStyles(BuildContext context) {
    const hSpace = HorizontalSpacing(0, 0);
    const vSpace = VerticalSpacing(4, 0);
    const lineSpace = VerticalSpacing(0, 0);
    final base = TextStyle(
      color: AppTheme.textPrimary.withValues(alpha: 0.92),
      fontSize: 14,
      height: 1.5,
    );
    return DefaultStyles(
      paragraph: DefaultTextBlockStyle(base, hSpace, vSpace, lineSpace, null),
      placeHolder: DefaultTextBlockStyle(
        base.copyWith(color: AppTheme.textMuted.withValues(alpha: 0.5)),
        hSpace,
        vSpace,
        lineSpace,
        null,
      ),
      h1: DefaultTextBlockStyle(
        base.copyWith(fontSize: 22, fontWeight: FontWeight.w800, height: 1.3),
        hSpace,
        const VerticalSpacing(10, 0),
        lineSpace,
        null,
      ),
      h2: DefaultTextBlockStyle(
        base.copyWith(fontSize: 18, fontWeight: FontWeight.w700, height: 1.35),
        hSpace,
        const VerticalSpacing(8, 0),
        lineSpace,
        null,
      ),
      h3: DefaultTextBlockStyle(
        base.copyWith(fontSize: 16, fontWeight: FontWeight.w700, height: 1.35),
        hSpace,
        const VerticalSpacing(6, 0),
        lineSpace,
        null,
      ),
      bold: const TextStyle(fontWeight: FontWeight.w700),
      italic: const TextStyle(fontStyle: FontStyle.italic),
      underline: const TextStyle(decoration: TextDecoration.underline),
      strikeThrough: const TextStyle(decoration: TextDecoration.lineThrough),
      link: const TextStyle(
        color: AppTheme.accent,
        decoration: TextDecoration.underline,
      ),
      quote: DefaultTextBlockStyle(
        base.copyWith(color: AppTheme.textMuted, fontStyle: FontStyle.italic),
        hSpace,
        vSpace,
        lineSpace,
        BoxDecoration(
          border: Border(left: BorderSide(color: AppTheme.accent.withValues(alpha: 0.55), width: 3)),
          color: Colors.white.withValues(alpha: 0.03),
        ),
      ),
      code: DefaultTextBlockStyle(
        base.copyWith(
          fontFamily: 'Consolas',
          fontSize: 12.5,
          color: const Color(0xFFE2E8F0),
        ),
        hSpace,
        vSpace,
        lineSpace,
        BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      inlineCode: InlineCodeStyle(
        style: base.copyWith(
          fontFamily: 'Consolas',
          fontSize: 12.5,
          color: const Color(0xFF7DD3FC),
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        radius: const Radius.circular(4),
      ),
      lists: DefaultListBlockStyle(
        base,
        hSpace,
        vSpace,
        lineSpace,
        null,
        null,
      ),
    );
  }
}

Document documentFromDescription(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return Document();

  if (descriptionLooksLikeHtml(text)) {
    try {
      final delta = HtmlToDelta().convert(text);
      final json = delta.toJson();
      if (json.isNotEmpty) return Document.fromJson(json);
    } catch (_) {
      final plain = descriptionPlainText(text);
      if (plain.isEmpty) return Document();
      final doc = Document();
      doc.insert(0, plain);
      return doc;
    }
  }

  final doc = Document();
  doc.insert(0, text);
  return doc;
}

String descriptionToHtml(QuillController controller) {
  final plain = controller.document.toPlainText().trim();
  if (plain.isEmpty) return '';

  try {
    final deltaJson = controller.document.toDelta().toJson();
    final ops = List<Map<String, dynamic>>.from(
      deltaJson.map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final html = QuillDeltaToHtmlConverter(ops).convert().trim();
    if (html.isEmpty || html == '<p><br/></p>' || html == '<p></p>') return '';
    return html;
  } catch (_) {
    return plain;
  }
}
