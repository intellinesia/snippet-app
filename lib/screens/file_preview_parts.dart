import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';

/// Middle truncation keeps both the start and the extension of a long name.
String middleTruncate(String name, int max) {
  if (name.length <= max) return name;
  final keep = max - 1;
  final head = (keep / 2).ceil();
  return '${name.substring(0, head)}…${name.substring(name.length - (keep - head))}';
}

Future<File> _toTemp(DaemonClient client, String path, String name) async {
  final bytes = await client.downloadFile(path);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/snippet-preview-$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<void> sharePreviewFile(
    BuildContext context, DaemonClient client, String path, String name) async {
  try {
    final f = await _toTemp(client, path, name);
    await SharePlus.instance
        .share(ShareParams(files: [XFile(f.path, name: name)]));
  } catch (_) {
    if (context.mounted) toast(context, "Couldn't share this file");
  }
}

Future<void> openPreviewFileIn(
    BuildContext context, DaemonClient client, String path, String name) async {
  try {
    final f = await _toTemp(client, path, name);
    await OpenFilex.open(f.path);
  } catch (_) {
    if (context.mounted) toast(context, "Couldn't open this file");
  }
}

/// The one preview bar, on the ground itself: close, the name centred and
/// truncated in the middle, share, more (open in, save, copy path).
class PreviewTopBar extends StatelessWidget {
  const PreviewTopBar({
    super.key,
    required this.client,
    required this.path,
    required this.name,
    required this.onClose,
    this.onSave,
    this.onEdit,
  });

  final DaemonClient client;
  final String path;
  final String name;
  final VoidCallback onClose;
  final VoidCallback? onSave;
  final VoidCallback? onEdit;

  Widget _icon(String icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox.square(
              dimension: 48,
              child: Center(child: AppIcon(icon, size: 20, color: AppColors.fg1))),
        ),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            _icon('x', 'Close', onClose),
            Expanded(
              child: Semantics(
                header: true,
                label: name,
                excludeSemantics: true,
                child: Text(middleTruncate(name, 32),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: sans(15, weight: W.label, color: AppColors.fg1)),
              ),
            ),
            _icon('share', 'Share',
                () => sharePreviewFile(context, client, path, name)),
            Builder(
              builder: (a) => _icon('more-horizontal', 'More', () async {
                final pick = await showAppMenu<String>(context,
                    anchor: a,
                    below: true,
                    alignEnd: true,
                    items: [
                      if (onEdit != null)
                        appMenuItem(value: 'edit', icon: 'edit', label: 'Edit'),
                      appMenuItem(
                          value: 'open', icon: 'external-link', label: 'Open in…'),
                      if (onSave != null)
                        appMenuItem(
                            value: 'save', icon: 'download', label: 'Save to device'),
                      appMenuItem(value: 'copy', icon: 'copy', label: 'Copy path'),
                    ]);
                if (!context.mounted) return;
                if (pick == 'open') openPreviewFileIn(context, client, path, name);
                if (pick == 'save') onSave?.call();
                if (pick == 'edit') onEdit?.call();
                if (pick == 'copy') {
                  await Clipboard.setData(ClipboardData(text: path));
                  if (context.mounted) toast(context, 'Path copied');
                }
              }),
            ),
          ]),
        ),
      );
}

const _languages = {
  'dart': 'Dart', 'py': 'Python', 'js': 'JavaScript', 'ts': 'TypeScript',
  'tsx': 'TypeScript', 'jsx': 'JavaScript', 'rs': 'Rust', 'go': 'Go',
  'swift': 'Swift', 'kt': 'Kotlin', 'java': 'Java', 'rb': 'Ruby',
  'sh': 'Shell', 'zsh': 'Shell', 'fish': 'Shell', 'json': 'JSON',
  'yaml': 'YAML', 'yml': 'YAML', 'toml': 'TOML', 'md': 'Markdown',
  'html': 'HTML', 'css': 'CSS', 'sql': 'SQL', 'c': 'C', 'h': 'C',
  'cpp': 'C++', 'txt': 'Text', 'csv': 'CSV', 'xml': 'XML',
};

String? languageForExt(String ext) => _languages[ext];

/// Why a kind has no preview, in one line.
(String, String) notPreviewable(String ext) {
  const archive = {'zip', 'tar', 'gz', 'tgz', 'bz2', 'xz', '7z', 'rar'};
  const office = {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'key', 'pages', 'numbers', 'odt', 'ods'};
  if (archive.contains(ext)) {
    return ('archive', 'Archives cannot be previewed here. Open it in another app.');
  }
  if (office.contains(ext)) {
    return ('file-text', 'Office documents cannot be previewed here yet.');
  }
  return ('file', 'This kind of file has no preview.');
}

/// No dead ends: an icon, one line on why, and what you can do instead.
class PreviewNotice extends StatelessWidget {
  const PreviewNotice({
    super.key,
    required this.icon,
    required this.title,
    this.line,
    this.actions = const [],
    this.progress,
  });

  final String icon;
  final String title;
  final String? line;
  final List<(String, VoidCallback, bool)> actions;

  /// A determinate bar under the title; null hides it.
  final double? progress;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(R.of(12))),
              child: Center(child: AppIcon(icon, size: 22, color: AppColors.fg2)),
            ),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: sans(15, weight: W.label, color: AppColors.fg1)),
            if (line != null) ...[
              const SizedBox(height: 4),
              Text(line!,
                  textAlign: TextAlign.center,
                  style: sans(13, color: AppColors.fg3)),
            ],
            if (progress != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    color: AppColors.fg2,
                    backgroundColor: AppColors.surface3,
                  ),
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (final (i, a) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Btn(a.$1,
                      variant: a.$3 ? BtnVariant.primary : BtnVariant.secondary,
                      onTap: a.$2),
                ],
              ]),
            ],
          ]),
        ),
      );
}

/// On-device PDF (PDFium via pdfrx): pages fit the width with 16 gutters and
/// 12 between, continuous scroll, pinch and double-tap zoom, a page pill.
class PdfPreview extends StatefulWidget {
  const PdfPreview(
      {super.key, required this.client, required this.path, required this.name});

  final DaemonClient client;
  final String path;
  final String name;

  @override
  State<PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<PdfPreview> {
  final _controller = PdfViewerController();
  Uint8List? _bytes;
  String? _error;
  int _page = 1;
  int _pages = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _bytes = null;
    });
    try {
      final b = await widget.client.downloadFile(widget.path);
      if (mounted) setState(() => _bytes = b);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _go(int page) {
    if (_pages == 0) return;
    final p = page.clamp(1, _pages);
    _controller.goToPage(pageNumber: p);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return PreviewNotice(
        icon: 'alert-triangle',
        title: 'Could not load the preview',
        line: 'The connection to the machine dropped. Try again.',
        actions: [
          ('Try again', _load, true),
          ('Open in…',
              () => openPreviewFileIn(context, widget.client, widget.path, widget.name),
              false),
        ],
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return const PreviewNotice(icon: 'file-text', title: 'Loading preview');
    }
    if (bytes.isEmpty) {
      return const PreviewNotice(
          icon: 'file-text',
          title: 'This file is empty',
          line: 'There is nothing to show.');
    }
    return Stack(children: [
      Positioned.fill(
        child: PdfViewer.data(
          bytes,
          sourceName: widget.path,
          controller: _controller,
          params: PdfViewerParams(
            margin: 12,
            backgroundColor: AppColors.bg,
            onViewerReady: (doc, c) =>
                setState(() => _pages = doc.pages.length),
            onPageChanged: (n) {
              if (n != null && n != _page) setState(() => _page = n);
            },
          ),
        ),
      ),
      if (_pages > 0)
        Positioned(
          left: 16,
          right: 16,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
          child: Center(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _arrow('chevron-left', 'Previous page', () => _go(_page - 1)),
                Semantics(
                  label: 'Page $_page of $_pages',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Page $_page of $_pages',
                        style: sans(14,
                            weight: W.label, color: AppColors.fg1, tabular: true)),
                  ),
                ),
                _arrow('chevron-right', 'Next page', () => _go(_page + 1)),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _arrow(String icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox.square(
              dimension: 48,
              child: Center(child: AppIcon(icon, size: 18, color: AppColors.fg1))),
        ),
      );
}
