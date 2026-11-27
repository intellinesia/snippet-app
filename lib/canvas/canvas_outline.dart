import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'canvas_models.dart';

/// One layer row in the outline: an element and its nesting depth.
class OutlineRow {
  const OutlineRow(this.element, this.depth);
  final CanvasElementRect element;
  final int depth;

  /// Human label: visible text, else tag, else id.
  String get label {
    final t = element.text.trim();
    if (t.isNotEmpty) return t.length > 40 ? '${t.substring(0, 40)}...' : t;
    return element.tag.isNotEmpty ? element.tag : element.id;
  }
}

const int kOutlineMaxRows = 400;
const int kOutlineMaxDepth = 4;
const double kCanvasOutlineWidth = 248;

/// Builds the layer tree from layout rects in document order. Depth counts the
/// rects that strictly contain an element (bigger area, or equal and earlier).
List<OutlineRow> buildOutline(List<CanvasElementRect> rects) {
  final usable = [
    for (final r in rects)
      if (r.id.isNotEmpty) r,
  ];
  final capped = usable.length > kOutlineMaxRows
      ? usable.sublist(0, kOutlineMaxRows)
      : usable;
  final rows = <OutlineRow>[];
  for (var i = 0; i < capped.length; i++) {
    final el = capped[i];
    var depth = 0;
    for (var j = 0; j < capped.length; j++) {
      if (i == j) continue;
      final o = capped[j];
      final bigger = o.area > el.area || (o.area == el.area && j < i);
      if (bigger &&
          o.bounds.inflate(0.5).contains(el.bounds.topLeft) &&
          o.bounds.inflate(0.5).contains(el.bounds.bottomRight)) {
        depth++;
      }
    }
    rows.add(
        OutlineRow(el, depth > kOutlineMaxDepth ? kOutlineMaxDepth : depth));
  }
  return rows;
}

/// Case-insensitive match on id, tag and text.
List<OutlineRow> filterOutline(List<OutlineRow> rows, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return rows;
  return [
    for (final r in rows)
      if (r.element.id.toLowerCase().contains(q) ||
          r.element.tag.toLowerCase().contains(q) ||
          r.element.text.toLowerCase().contains(q))
        r,
  ];
}

/// Case-insensitive match on frame title and id.
List<CanvasFrame> filterFrames(List<CanvasFrame> frames, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return frames;
  return [
    for (final f in frames)
      if (f.title.toLowerCase().contains(q) || f.id.toLowerCase().contains(q))
        f,
  ];
}

/// Left rail: search, frames, and layers of the selected frame by data-cv-id.
class CanvasOutlineRail extends StatefulWidget {
  const CanvasOutlineRail({
    super.key,
    required this.frames,
    required this.selectedFrameId,
    required this.selectedElementId,
    required this.layers,
    required this.layersLoading,
    required this.onSelectFrame,
    required this.onSelectElement,
    this.onCollapse,
  });

  final List<CanvasFrame> frames;
  final String? selectedFrameId;
  final String? selectedElementId;
  final List<CanvasElementRect>? layers;
  final bool layersLoading;
  final ValueChanged<CanvasFrame> onSelectFrame;
  final ValueChanged<CanvasElementRect> onSelectElement;

  /// Hides the rail back to the icon strip.
  final VoidCallback? onCollapse;

  @override
  State<CanvasOutlineRail> createState() => _CanvasOutlineRailState();
}

class _CanvasOutlineRailState extends State<CanvasOutlineRail> {
  final _controller = TextEditingController();
  String _query = '';
  List<CanvasElementRect>? _outlineSource;
  List<OutlineRow> _rows = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<OutlineRow> get _allRows {
    if (!identical(_outlineSource, widget.layers)) {
      _outlineSource = widget.layers;
      _rows = widget.layers == null ? const [] : buildOutline(widget.layers!);
    }
    return _rows;
  }

  @override
  Widget build(BuildContext context) {
    final frames = filterFrames(widget.frames, _query);
    final selected =
        widget.frames.where((f) => f.id == widget.selectedFrameId).firstOrNull;
    final rows = filterOutline(_allRows, _query);
    return Container(
      width: kCanvasOutlineWidth,
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(right: BorderSide(color: AppColors.paneLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: PaneRow.height,
            padding: EdgeInsets.fromLTRB(S.s12, 0, S.s4, 0),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.paneLine)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Outline',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(PaneRow.label,
                          weight: W.label, color: PaneRow.labelOn)),
                ),
                if (widget.onCollapse != null)
                  Semantics(
                    button: true,
                    label: 'Hide outline',
                    excludeSemantics: true,
                    child: IconBtn('panel-left',
                        size: 28,
                        iconSize: 13,
                        tooltip: 'Hide outline',
                        onTap: widget.onCollapse),
                  ),
              ],
            ),
          ),
          Container(
            height: 32,
            padding: EdgeInsets.symmetric(horizontal: S.s12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.paneLine)),
            ),
            child: Row(
              children: [
                AppIcon('search', size: 13, color: AppColors.fg4),
                SizedBox(width: S.s8),
                Expanded(
                  child: Semantics(
                    textField: true,
                    label: 'Find a frame or element',
                    child: TextField(
                      controller: _controller,
                      onChanged: (v) => setState(() => _query = v),
                      style: sans(PaneRow.label, color: PaneRow.labelOn),
                      cursorColor: PaneRow.labelOn,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Find a frame or element',
                        hintStyle: sans(PaneRow.label, color: AppColors.fg4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: S.s16),
              children: [
                _header('Frames', canvasCount(frames.length, 'frame')),
                if (frames.isEmpty) _empty('No frames match'),
                for (final f in frames)
                  _row(
                    icon: 'grid',
                    label: f.title.isNotEmpty ? f.title : f.id,
                    selected: f.id == widget.selectedFrameId,
                    semantic: 'Frame ${f.title.isNotEmpty ? f.title : f.id}',
                    onTap: () => widget.onSelectFrame(f),
                  ),
                if (selected != null) ...[
                  SizedBox(height: S.s8),
                  Divider(height: 1, thickness: 1, color: AppColors.paneLine),
                  _header(
                      '${selected.title.isNotEmpty ? selected.title : selected.id} · layers',
                      null),
                  if (widget.layersLoading && widget.layers == null)
                    _empty('Loading layers'),
                  if (!widget.layersLoading && widget.layers == null)
                    _empty('Layers unavailable'),
                  if (widget.layers != null && rows.isEmpty)
                    _empty(_query.isEmpty ? 'No layers' : 'No layers match'),
                  for (final r in rows)
                    _row(
                      label: r.label,
                      trailing: r.element.id,
                      indent: r.depth * 12.0,
                      selected: r.element.id == widget.selectedElementId,
                      semantic: 'Layer ${r.label}, ${r.element.id}',
                      onTap: () => widget.onSelectElement(r.element),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(String title, String? trailing) => Padding(
        padding: EdgeInsets.fromLTRB(S.s12, S.s12, S.s12, S.s4),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, weight: W.label, color: AppColors.fg3)),
            ),
            if (trailing != null)
              Text(trailing, style: sans(12, color: AppColors.fg4)),
          ],
        ),
      );

  Widget _empty(String text) => Padding(
        padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s16),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: sans(12, color: AppColors.fg4)),
        ),
      );

  Widget _row({
    required String label,
    required bool selected,
    required String semantic,
    required VoidCallback onTap,
    String? icon,
    String? trailing,
    double indent = 0,
  }) =>
      Padding(
        padding: EdgeInsets.symmetric(horizontal: S.s4),
        child: Semantics(
          button: true,
          selected: selected,
          label: semantic,
          excludeSemantics: true,
          child: Material(
            color: selected
                ? (kMobile ? AppColors.surface3 : PaneRow.plate)
                : Colors.transparent,
            borderRadius:
                BorderRadius.circular(kMobile ? R.sm : PaneRow.radius),
            child: InkWell(
              onTap: onTap,
              borderRadius:
                  BorderRadius.circular(kMobile ? R.sm : PaneRow.radius),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: kMobile ? 44 : 28),
                child: Padding(
                  padding: EdgeInsets.only(left: S.s8 + indent, right: S.s8),
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        AppIcon(icon,
                            size: kMobile ? 15 : 13, color: AppColors.fg4),
                        SizedBox(width: S.s8),
                      ],
                      Expanded(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(13,
                                weight: selected ? W.label : W.body,
                                color: selected
                                    ? (kMobile
                                        ? AppColors.fg1
                                        : PaneRow.labelOn)
                                    : (kMobile
                                        ? AppColors.fg2
                                        : PaneRow.labelOff))),
                      ),
                      if (trailing != null) ...[
                        SizedBox(width: S.s8),
                        Text(trailing,
                            style: mono(kMobile ? 11 : 12,
                                color:
                                    selected ? AppColors.fg3 : AppColors.fg4)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
