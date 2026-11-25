import 'package:flutter/material.dart';

import '../phosphor_icons.dart';
import '../tap_detector.dart';
import '../theme.dart';

class ShellUsageItem {
  const ShellUsageItem({
    required this.label,
    required this.usedPercent,
    this.resetsAt,
  });

  final String label;
  final double usedPercent;
  final DateTime? resetsAt;
}

class ShellStatusBar extends StatelessWidget {
  const ShellStatusBar({
    super.key,
    this.usage = const <ShellUsageItem>[],
    this.needsYouCount = 0,
    this.connected = true,
    this.daemonDown = false,
    this.hostsOnline = 0,
    this.hostsTotal = 0,
    this.rightPanelEnabled = true,
    this.onOpenUsage,
    this.onRefreshUsage,
    this.onOpenNeedsYou,
    this.onOpenTerminal,
    this.onOpenHosts,
    this.onToggleRightPanel,
    this.onRetry,
  });

  final List<ShellUsageItem> usage;
  final int needsYouCount;
  final bool connected;
  final bool daemonDown;
  final int hostsOnline;
  final int hostsTotal;
  final bool rightPanelEnabled;
  final VoidCallback? onOpenUsage;
  final VoidCallback? onRefreshUsage;
  final VoidCallback? onOpenNeedsYou;
  final VoidCallback? onOpenTerminal;
  final VoidCallback? onOpenHosts;
  final VoidCallback? onToggleRightPanel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final warning = _firstNearLimit(usage);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _StatusStaticItem(
          child: Text('Used', style: sans(11, color: AppColors.fg3)),
        ),
        const SizedBox(width: 12),
        for (var i = 0; i < usage.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          _UsageMeter(item: usage[i], onTap: onOpenUsage),
        ],
        if (usage.isNotEmpty) const SizedBox(width: 12),
        _StatusIconTarget(
          key: const ValueKey('shell-status-refresh-usage'),
          icon: PhIcons.arrowClockwise,
          tooltip: 'Refresh usage',
          semanticLabel: 'Refresh usage',
          color: AppColors.fg3,
          onTap: onRefreshUsage,
        ),
        if (warning != null) ...[
          const SizedBox(width: 12),
          _NearLimit(item: warning),
        ],
        const Spacer(),
        if (daemonDown) ..._daemonDownItems() else ..._rightItems(),
      ],
    );
  }

  List<Widget> _daemonDownItems() => [
        _StatusStaticItem(
          child: Text('Reconnecting...', style: sans(11, color: AppColors.fg1)),
        ),
        const SizedBox(width: 12),
        _StatusTextTarget(
          text: 'Retry',
          tooltip: 'Retry connection',
          semanticLabel: 'Retry connection',
          style: sans(11, weight: W.label, color: AppColors.fg1),
          onTap: onRetry,
        ),
      ];

  List<Widget> _rightItems() {
    final items = <Widget>[];
    if (needsYouCount > 0) {
      items.add(_NeedsYou(count: needsYouCount, onTap: onOpenNeedsYou));
      items.add(const SizedBox(width: 12));
    }
    items.add(_AgentConnection(connected: connected));
    items.add(const SizedBox(width: 12));
    items.add(_StatusIconTarget(
      key: const ValueKey('shell-status-open-terminal'),
      icon: PhIcons.terminal,
      tooltip: 'Open terminal',
      semanticLabel: 'Open terminal',
      onTap: onOpenTerminal,
    ));
    items.add(const SizedBox(width: 12));
    items.add(_HostsItem(
      online: hostsOnline,
      total: hostsTotal,
      onTap: onOpenHosts,
    ));
    items.add(const SizedBox(width: 12));
    items.add(_StatusIconTarget(
      key: const ValueKey('shell-status-toggle-right-panel'),
      icon: PhIcons.sidebarSimple,
      flipX: true,
      tooltip: 'Toggle right panel',
      semanticLabel: 'Toggle right panel',
      onTap: rightPanelEnabled ? onToggleRightPanel : null,
    ));
    return items;
  }
}

ShellUsageItem? _firstNearLimit(List<ShellUsageItem> usage) {
  for (final item in usage) {
    if (item.usedPercent >= 91) return item;
  }
  return null;
}

String _percentText(double usedPercent) =>
    '${usedPercent.clamp(0, 100).round()}%';

String _clockText(DateTime at) {
  final local = at.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class _UsageMeter extends StatelessWidget {
  const _UsageMeter({required this.item, this.onTap});

  final ShellUsageItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final nearLimit = item.usedPercent >= 91;
    final label = '${item.label} ${_percentText(item.usedPercent)}';
    return _StatusTarget(
      tooltip: 'Open usage',
      semanticLabel: '$label usage',
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (nearLimit) ...[
            Icon(PhIcons.warning, size: 11, color: AppColors.fg1),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            maxLines: 1,
            style: sans(
              11,
              weight: nearLimit ? W.label : W.body,
              color: nearLimit ? AppColors.fg1 : AppColors.fg2,
            ),
          ),
        ],
      ),
    );
  }
}

class _NearLimit extends StatelessWidget {
  const _NearLimit({required this.item});

  final ShellUsageItem item;

  @override
  Widget build(BuildContext context) {
    final reset = item.resetsAt;
    final text = reset == null
        ? 'Near limit'
        : 'Near limit, resets ${_clockText(reset)}';
    return _StatusStaticItem(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhIcons.warning, size: 11, color: AppColors.fg1),
          const SizedBox(width: 4),
          Text(
            text,
            maxLines: 1,
            style: sans(11, weight: W.label, color: AppColors.fg1),
          ),
        ],
      ),
    );
  }
}

class _NeedsYou extends StatelessWidget {
  const _NeedsYou({required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = count == 1 ? '1 needs you' : '$count need you';
    return _StatusTarget(
      key: const ValueKey('shell-status-needs-you'),
      tooltip: 'Open needs you',
      semanticLabel: text,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            maxLines: 1,
            style: sans(11, weight: W.label, color: AppColors.fg2),
          ),
        ],
      ),
    );
  }
}

class _AgentConnection extends StatelessWidget {
  const _AgentConnection({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return _StatusStaticItem(
      tooltip: connected ? 'Agent connected' : 'Agent offline',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Agent', style: sans(11, color: AppColors.fg2)),
          const SizedBox(width: 6),
          if (connected)
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: AppColors.fg2, shape: BoxShape.circle),
            )
          else
            Icon(PhIcons.wifiSlash, size: 11, color: AppColors.fg2),
        ],
      ),
    );
  }
}

class _HostsItem extends StatelessWidget {
  const _HostsItem({required this.online, required this.total, this.onTap});

  final int online;
  final int total;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final offline = online < total;
    final onlineCount = total > 0 ? total : online;
    final text = offline
        ? '$online of $total hosts online'
        : onlineCount == 1
            ? '1 host'
            : '$onlineCount hosts';
    return _StatusTarget(
      key: const ValueKey('shell-status-hosts'),
      tooltip: 'Open hosts',
      semanticLabel: text,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (offline)
            const _UnplugGlyph(key: ValueKey('shell-status-unplug-glyph'))
          else
            Icon(PhIcons.hardDrives, size: 12, color: AppColors.fg2),
          const SizedBox(width: 5),
          Text(
            text,
            maxLines: 1,
            style: sans(
              11,
              weight: offline ? W.label : W.body,
              color: offline ? AppColors.fg1 : AppColors.fg2,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnplugGlyph extends StatelessWidget {
  const _UnplugGlyph({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(12, 12),
        painter: _UnplugPainter(color: AppColors.fg1),
      );
}

class _UnplugPainter extends CustomPainter {
  const _UnplugPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 16, size.height / 16);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(6, 2.5)
      ..lineTo(6, 5.5)
      ..moveTo(10, 2.5)
      ..lineTo(10, 5.5)
      ..moveTo(4.5, 5.5)
      ..lineTo(11.5, 5.5)
      ..lineTo(11.5, 7.5)
      ..arcToPoint(
        const Offset(4.5, 7.5),
        radius: const Radius.circular(3.5),
      )
      ..lineTo(4.5, 5.5)
      ..close()
      ..moveTo(8, 11)
      ..lineTo(8, 13.5);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_UnplugPainter oldDelegate) => color != oldDelegate.color;
}

class _StatusIconTarget extends StatelessWidget {
  const _StatusIconTarget({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    this.onTap,
    this.color,
    this.flipX = false,
  });

  final IconData icon;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback? onTap;
  final Color? color;
  final bool flipX;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final iconColor = enabled ? color ?? AppColors.fg2 : AppColors.fg3;
    Widget glyph = Icon(icon, size: 12, color: iconColor);
    if (flipX) {
      glyph = Transform.flip(flipX: true, child: glyph);
    }
    return _StatusTarget(
      tooltip: tooltip,
      semanticLabel: semanticLabel,
      iconOnly: true,
      onTap: onTap,
      child: glyph,
    );
  }
}

class _StatusTextTarget extends StatelessWidget {
  const _StatusTextTarget({
    required this.text,
    required this.tooltip,
    required this.semanticLabel,
    required this.style,
    this.onTap,
  });

  final String text;
  final String tooltip;
  final String semanticLabel;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _StatusTarget(
        tooltip: tooltip,
        semanticLabel: semanticLabel,
        onTap: onTap,
        child: Text(text, maxLines: 1, style: style),
      );
}

class _StatusStaticItem extends StatelessWidget {
  const _StatusStaticItem({required this.child, this.tooltip});

  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget result = SizedBox(
      height: 24,
      child: Center(widthFactor: 1, child: child),
    );
    if (tooltip != null) result = Tooltip(message: tooltip!, child: result);
    return result;
  }
}

class _StatusTarget extends StatefulWidget {
  const _StatusTarget({
    super.key,
    required this.child,
    required this.tooltip,
    required this.semanticLabel,
    this.onTap,
    this.iconOnly = false,
  });

  final Widget child;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback? onTap;
  final bool iconOnly;

  @override
  State<_StatusTarget> createState() => _StatusTargetState();
}

class _StatusTargetState extends State<_StatusTarget> {
  bool _hover = false;
  bool _focus = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final fill = !enabled
        ? Colors.transparent
        : _down
            ? AppColors.surface3
            : (_hover || _focus)
                ? AppColors.hoverPlate
                : Colors.transparent;
    Widget result = FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      onShowHoverHighlight: (value) => setState(() => _hover = value),
      onShowFocusHighlight: (value) => setState(() => _focus = value),
      child: Semantics(
        button: enabled,
        enabled: enabled,
        label: widget.semanticLabel,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          child: Container(
            width: widget.iconOnly ? 24 : null,
            height: 24,
            constraints:
                widget.iconOnly ? null : const BoxConstraints(minWidth: 24),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(widthFactor: 1, child: widget.child),
          ),
        ),
      ),
    );
    return Tooltip(message: widget.tooltip, child: result);
  }
}
