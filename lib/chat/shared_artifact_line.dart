// A share_artifact step as one line: "Shared" and the artifact as a chip
// with a single action; images add a small thumbnail underneath.

import '../platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../screens/artifact_viewer.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'desktop_rich_cards.dart';

enum SharedArtifactKind { file, image, apk, link }

String _extOf(String name) {
  final base = name.split('/').last;
  final dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) return '';
  final ext = base.substring(dot + 1).toLowerCase();
  return ext.length > 5 || ext.contains(' ') ? '' : ext;
}

SharedArtifactKind sharedArtifactKind(String kind, String name) {
  if (kind == 'image' || kind == 'svg') return SharedArtifactKind.image;
  if (kind == 'html') return SharedArtifactKind.link;
  if (_extOf(name) == 'apk') return SharedArtifactKind.apk;
  return SharedArtifactKind.file;
}

/// The verb before the chip, naming the recipient unless it is the user.
String sharedArtifactVerb(String to) {
  if (to.isEmpty || to == 'human' || to.startsWith('channel:')) {
    return 'Shared';
  }
  if (to.startsWith('group:')) return 'Shared in group';
  return 'Shared with $to';
}

class SharedArtifactLine extends StatefulWidget {
  const SharedArtifactLine({
    super.key,
    required this.client,
    required this.session,
    required this.id,
    required this.version,
    required this.title,
    required this.kind,
    this.url = '',
    this.to = '',
  });

  final DaemonClient client;
  final String session;
  final String id;
  final int version;
  final String title;
  final String kind;

  /// The signed link from the share payload; looked up when missing.
  final String url;
  final String to;

  @override
  State<SharedArtifactLine> createState() => _SharedArtifactLineState();
}

class _SharedArtifactLineState extends State<SharedArtifactLine> {
  String _entry = '';
  String _url = '';
  bool _lookedUp = false;
  bool _lookupFailed = false;

  @override
  void initState() {
    super.initState();
    _url = widget.url;
    // The title may not carry the file name, and old events lack the link.
    if (_url.isEmpty || _extOf(widget.title).isEmpty) _lookUp();
  }

  Future<void> _lookUp() async {
    try {
      final all = await widget.client.artifacts(widget.session);
      final a = all.where((a) => a.id == widget.id).firstOrNull;
      final v = a?.version(widget.version);
      if (!mounted) return;
      if (v == null) {
        setState(() {
          _lookedUp = true;
          _lookupFailed = false;
        });
        return;
      }
      setState(() {
        _entry = v.source.isNotEmpty ? v.source : v.entry;
        if (_url.isEmpty) _url = v.url;
        _lookupFailed = false;
      });
    } catch (_) {
      if (mounted && _url.isEmpty) {
        setState(() {
          _lookedUp = true;
          _lookupFailed = true;
        });
      }
    }
  }

  void _retryLookUp() {
    setState(() {
      _lookedUp = false;
      _lookupFailed = false;
    });
    _lookUp();
  }

  String get _name => _extOf(widget.title).isNotEmpty ? widget.title : _entry;

  SharedArtifactKind get _kind => sharedArtifactKind(widget.kind, _name);

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _open() => openArtifact(context,
      client: widget.client,
      session: widget.session,
      id: widget.id,
      version: widget.version);

  // The browser fetches the signed link and hands an APK to the installer.
  void _download() {
    if (_url.isEmpty) return _open();
    launchUrl(widget.client.artifactUri(_url),
        mode: LaunchMode.externalApplication);
  }

  String get _meta {
    final ext = _extOf(_name);
    return switch (_kind) {
      SharedArtifactKind.link => 'web page',
      SharedArtifactKind.apk => 'Android',
      _ => [
          if (ext.isNotEmpty && _extOf(widget.title) != ext) '.$ext',
          if (widget.version > 1) 'v${widget.version}',
        ].join(' · '),
    };
  }

  Widget _pill(String label, VoidCallback onTap, {bool primary = false}) =>
      Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          onTap: onTap,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary ? AppColors.accent : AppColors.surface3,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(label,
                style: sans(12,
                    weight: W.label,
                    height: 1,
                    color: primary ? AppColors.accentFg : AppColors.fg1)),
          ),
        ),
      );

  Widget _chip() {
    final kind = _kind;
    final (icon, iconColor) = switch (kind) {
      SharedArtifactKind.apk => ('package', AppColors.fg2),
      SharedArtifactKind.link => ('link', AppColors.fg2),
      SharedArtifactKind.image => ('image', AppColors.fg2),
      SharedArtifactKind.file => (artifactIcon(widget.kind), AppColors.fg2),
    };
    final action = switch (kind) {
      SharedArtifactKind.apk =>
        _pill(_android ? 'Install' : 'Download', _download, primary: true),
      SharedArtifactKind.image => null,
      _ => _pill('Open', _open),
    };
    final meta = _meta;
    if (!kMobile) {
      return TapDetector(
        onTap: _open,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: AppIcon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title.isEmpty ? 'Artifact' : widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13,
                          weight: FontWeight.w500,
                          height: 18 / 13,
                          color: PaneRow.labelOn)),
                  if (meta.isNotEmpty)
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, height: 16 / 12, color: AppColors.fg4)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (kind == SharedArtifactKind.apk)
              DesktopRichButton(_android ? 'Install' : 'Download',
                  variant: DesktopRichButtonVariant.primary, onTap: _download)
            else if (kind != SharedArtifactKind.image)
              DesktopRichButton('Open',
                  variant: DesktopRichButtonVariant.ghost, onTap: _open)
            else
              AppIcon('chevron-down', size: 14, color: AppColors.fg3),
          ]),
        ),
      );
    }
    if (kMobile) {
      return TapDetector(
        onTap: _open,
        child: Container(
          width: double.infinity,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            AppIcon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.title.isEmpty ? 'Artifact' : widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, weight: FontWeight.w500, color: AppColors.fg1),
              ),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(meta, style: sans(12, color: AppColors.fg3)),
            ],
            const SizedBox(width: 8),
            AppIcon('chevron-right', size: 14, color: AppColors.fg3),
          ]),
        ),
      );
    }
    return TapDetector(
      onTap: _open,
      child: Container(
        height: kMobile ? 36 : 30,
        padding: EdgeInsets.only(left: 10, right: action == null ? 12 : 5),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(kMobile ? 18 : 15),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.title.isEmpty ? 'Artifact' : widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(kMobile ? 14 : 13,
                  weight: W.label, color: AppColors.fg1),
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(meta, style: codeMono(12, color: AppColors.fg4)),
          ],
          if (action != null) ...[const SizedBox(width: 8), action],
        ]),
      ),
    );
  }

  Widget _thumb() {
    final Widget child = _url.isEmpty
        ? (_lookupFailed
            ? LoadFailed(message: 'Couldn’t load', onRetry: _retryLookUp)
            : _lookedUp
                ? Center(
                    child: AppIcon('image', size: 20, color: AppColors.fg4))
                : const LoadingBlock(spinner: true))
        : ArtifactImage(client: widget.client, url: _url);
    return TapDetector(
      onTap: _open,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ColoredBox(
          color: AppColors.surface1,
          child: SizedBox(width: 200, height: 120, child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, c) => Row(children: [
            // A long recipient gives way to the artifact's title.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth * 0.3),
              child: Text(sharedArtifactVerb(widget.to),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 14 : 13, color: AppColors.fg3)),
            ),
            const SizedBox(width: 8),
            Flexible(child: _chip()),
          ]),
        ),
        if (_kind == SharedArtifactKind.image) ...[
          const SizedBox(height: 8),
          _thumb(),
        ],
      ],
    );
  }
}
