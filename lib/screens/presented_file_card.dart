import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/chat_card.dart';
import '../composer/desktop_composer.dart' show DeskIconButton;
import '../media_views.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'file_viewer.dart';
import '../tap_detector.dart';

/// A file the agent handed over with `present_file`: a card on a phone and a
/// compact line on desktop, opening the file, with a download button.
class PresentedFileCard extends StatelessWidget {
  const PresentedFileCard({
    super.key,
    required this.client,
    required this.path,
    required this.caption,
    this.onOpenFileTab,
    this.grouped = false,
  });

  final DaemonClient client;
  final String path;
  final String caption;
  final bool grouped;
  final void Function(String path, String name)? onOpenFileTab;

  String get _name => path.split('/').last;

  String get _ext {
    final dot = _name.lastIndexOf('.');
    return dot > 0 ? _name.substring(dot + 1).toLowerCase() : '';
  }

  String get _icon => switch (_ext) {
        'md' || 'markdown' || 'txt' || 'rst' || 'doc' || 'docx' => 'file-text',
        'html' || 'htm' => 'globe',
        'pdf' => 'pdf',
        'csv' || 'tsv' || 'xls' || 'xlsx' => 'list',
        'zip' || 'tar' || 'gz' || 'tgz' || 'apk' || 'dmg' => 'archive',
        'mp4' || 'mov' || 'webm' || 'mkv' => 'film',
        'mp3' || 'wav' || 'm4a' || 'ogg' => 'music',
        'json' ||
        'yaml' ||
        'yml' ||
        'toml' ||
        'rs' ||
        'dart' ||
        'py' ||
        'js' ||
        'ts' ||
        'tsx' ||
        'go' ||
        'sh' ||
        'sql' =>
          'file-code',
        _ => 'file',
      };

  void _open(BuildContext context) {
    if (openFileForViewing(context, client: client, path: path, name: _name)) {
      return;
    }
    if (onOpenFileTab != null) {
      onOpenFileTab!(path, _name);
      return;
    }
    presentFileOnDesktop(context, client: client, path: path, name: _name);
  }

  Future<void> _download(BuildContext context) async {
    try {
      toast(context, 'Downloading $_name…');
      final msg = await downloadRemoteFileWithCancel(context, client,
          path: path, name: _name);
      if (msg != null && context.mounted) toast(context, msg);
    } catch (e) {
      if (context.mounted) toast(context, '$e', danger: true);
    }
  }

  String get _kindLabel => switch (_icon) {
        'file-text' => 'Document',
        'globe' => 'Web page',
        'pdf' => 'PDF',
        'list' => 'Table',
        'archive' => 'Archive',
        'film' => 'Video',
        'music' => 'Audio',
        'file-code' => 'Code',
        _ => _ext.isEmpty ? 'File' : _ext.toUpperCase(),
      };

  Widget _downloadButton(BuildContext context) => Tooltip(
        message: 'Download',
        child: Pressable(
          child: InkWell(
            onTap: () => _download(context),
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: kMobile ? 48 : 28,
              height: kMobile ? 48 : 28,
              child: Center(
                child: Container(
                  width: kMobile ? 36 : 28,
                  height: kMobile ? 36 : 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.surface3, shape: BoxShape.circle),
                  child: AppIcon('download',
                      size: kMobile ? 16 : 14, color: AppColors.fg2),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (mediaKindOf(path) == MediaKind.image) return _image(context);
    return Tooltip(
      message: path,
      waitDuration: const Duration(milliseconds: 600),
      child: grouped
          ? MediaRow(
              icon: _icon,
              name: _name,
              detail: [_kindLabel, if (caption.isNotEmpty) caption].join(' · '),
              grouped: true,
              onTap: () => _open(context),
              trailing: _downloadButton(context),
            )
          : !kMobile
              ? _deskRow(context)
              : ChatCard(children: [
                  ChatCardFooter(
                    title: _name,
                    meta: [_kindLabel, if (caption.isNotEmpty) caption]
                        .join(' · '),
                    leading: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: AppColors.surface3,
                          borderRadius: BorderRadius.circular(R.card)),
                      child: AppIcon(_icon, size: 20, color: AppColors.fg2),
                    ),
                    trailing: _downloadButton(context),
                    divider: false,
                    onTap: () => _open(context),
                  ),
                ]),
    );
  }

  /// Desktop, several files: one 32pt row with a 20pt thumbnail (or the
  /// file kind's icon), name over caption, and a bare download target.
  Widget deskThumbRow(BuildContext context) {
    final isImage = mediaKindOf(path) == MediaKind.image;
    final sub = caption.isNotEmpty ? caption : _kindLabel;
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(7),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 2, 0),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox.square(
                  dimension: 20,
                  child: isImage
                      // The row opens it; the thumb only shows it.
                      ? IgnorePointer(
                          child: ImageThumb(
                              client: client,
                              path: path,
                              width: 20,
                              height: 20))
                      : ColoredBox(
                          color: AppColors.surface3,
                          child: Center(
                              child: AppIcon(_icon,
                                  size: 13, color: AppColors.fg2))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: _name,
                        style: mono(12, weight: W.label, color: AppColors.fg1)),
                    if (sub.isNotEmpty)
                      TextSpan(
                          text: '  $sub',
                          style: sans(11, color: AppColors.fg3)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              DeskIconButton('download',
                  tooltip: 'Download',
                  iconSize: 13,
                  onTap: () => _download(context)),
            ]),
          ),
        ),
      ),
    );
  }

  /// Desktop: one 30pt TC row in the tool rows' language, not a big card.
  Widget _deskRow(BuildContext context) {
    final meta = [_kindLabel, if (caption.isNotEmpty) caption].join(' · ');
    final radius = BorderRadius.circular(7);
    return Material(
      color: AppColors.surface1,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.fromLTRB(10, 0, 2, 0),
          child: Row(children: [
            SizedBox(
              width: 14,
              height: 14,
              child:
                  Center(child: AppIcon(_icon, size: 13, color: AppColors.fg2)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: _name,
                      style: mono(12, weight: W.label, color: AppColors.fg1)),
                  if (meta.isNotEmpty)
                    TextSpan(
                        text: '  $meta', style: sans(11, color: AppColors.fg3)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: S.s8),
            _downloadButton(context),
          ]),
        ),
      ),
    );
  }

  Widget _image(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s6),
      child: SizedBox(
        width: double.infinity,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SingleImage(client: client, path: path),
          SizedBox(height: S.s4),
          Row(children: [
            Expanded(
              child: Text(caption.isNotEmpty ? caption : _name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TS.meta(AppColors.fg3)),
            ),
            _downloadButton(context),
          ]),
        ]),
      ),
    );
  }
}

class MediaRow extends StatelessWidget {
  const MediaRow({
    super.key,
    required this.icon,
    required this.name,
    required this.detail,
    required this.onTap,
    this.trailing,
    this.grouped = false,
  });

  final String icon;
  final String name;
  final String detail;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: kMobile ? 60 : 30),
        child: Padding(
          padding: EdgeInsets.fromLTRB(kMobile ? S.s12 : 10, kMobile ? S.s8 : 0,
              kMobile ? S.of(10) : 8, kMobile ? S.s8 : 0),
          child: Row(children: [
            Container(
              width: kMobile ? 28 : 14,
              height: kMobile ? 36 : 14,
              alignment: Alignment.center,
              child:
                  AppIcon(icon, size: kMobile ? 20 : 13, color: AppColors.fg2),
            ),
            SizedBox(width: kMobile ? S.s12 : 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(kMobile ? 14 : 13,
                          weight: W.label, color: AppColors.fg1)),
                  if (detail.isNotEmpty) ...[
                    SizedBox(height: S.s2),
                    Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(kMobile ? 13 : 12, color: AppColors.fg4)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              SizedBox(width: S.s8),
              trailing!,
            ],
          ]),
        ),
      ),
    );
    if (grouped) {
      return Pressable(
          kind: PressKind.row,
          child: Material(color: Colors.transparent, child: row));
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: kMobile ? S.s4 : S.of(3)),
      child: Pressable(
        kind: PressKind.card,
        radius: 12,
        child: Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.lg),
          clipBehavior: Clip.antiAlias,
          child: row,
        ),
      ),
    );
  }
}

/// Files sent in one go: a single file is its own row; several share a header
/// and show the first few, with the rest a tap away.
class PresentedFiles extends StatefulWidget {
  const PresentedFiles({
    super.key,
    required this.client,
    required this.files,
    this.onOpenFileTab,
  });

  final DaemonClient client;
  final List<({String path, String caption})> files;
  final void Function(String path, String name)? onOpenFileTab;

  @override
  State<PresentedFiles> createState() => _PresentedFilesState();
}

class _PresentedFilesState extends State<PresentedFiles> {
  static const _shown = 3;
  bool _all = false;

  /// Desktop: a quiet count line, then one row per file, no shared box.
  Widget _desk(List<({String path, String caption})> visible, int hidden) {
    final files = widget.files;
    Widget link(String label, VoidCallback onTap) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(label, style: sans(12, color: AppColors.fg3)),
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 6),
                child: Row(children: [
                  Text('${files.length} files',
                      style: sans(12, color: AppColors.fg4)),
                  const SizedBox(width: 10),
                  link('Download all', _downloadAll),
                ]),
              ),
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) const SizedBox(height: 4),
                PresentedFileCard(
                  client: widget.client,
                  path: visible[i].path,
                  caption: visible[i].caption,
                  onOpenFileTab: widget.onOpenFileTab,
                ).deskThumbRow(context),
              ],
              if (hidden > 0 || (_all && files.length > _shown))
                Padding(
                  padding: const EdgeInsets.only(left: 2, top: 6),
                  child: Row(children: [
                    link(_all ? 'Show fewer' : 'Show $hidden more',
                        () => setState(() => _all = !_all)),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadAll() async {
    try {
      toast(context, 'Preparing ${widget.files.length} files…');
      final path = await widget.client
          .zipFiles('files', [for (final f in widget.files) f.path]);
      if (!mounted) return;
      final msg = await downloadRemoteFileWithCancel(context, widget.client,
          path: path, name: 'files.zip');
      if (msg != null && mounted) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Widget _row(({String path, String caption}) f, {bool grouped = false}) =>
      PresentedFileCard(
        client: widget.client,
        path: f.path,
        caption: f.caption,
        onOpenFileTab: widget.onOpenFileTab,
        grouped: grouped,
      );

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    if (files.length == 1) return _row(files.first);
    final visible = _all ? files : files.take(_shown).toList();
    final hidden = files.length - visible.length;
    if (!kMobile) return _desk(visible, hidden);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(S.s2, S.s4, 0, S.s2),
          child: Row(children: [
            Expanded(
              child: Text('Shared ${files.length} files',
                  style: TS.meta(AppColors.fg3)),
            ),
            TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _downloadAll,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s2),
                child: Text('Download all', style: TS.meta(AppColors.accent)),
              ),
            ),
          ]),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: S.s4),
          child: Material(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.lg),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) Container(height: 1, color: AppColors.line),
                _row(visible[i], grouped: true),
              ],
            ]),
          ),
        ),
        if (hidden > 0 || (_all && files.length > _shown))
          TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _all = !_all),
            child: Padding(
              padding: EdgeInsets.fromLTRB(S.s2, S.s4, 0, S.s4),
              child: Text(_all ? 'Show fewer' : 'Show $hidden more',
                  style: TS.meta(AppColors.accent)),
            ),
          ),
      ],
    );
  }
}
