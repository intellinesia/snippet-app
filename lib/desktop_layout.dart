import 'package:flutter/material.dart';
import 'phosphor_icons.dart';

import 'platform.dart';
import 'settings_form.dart';
import 'theme.dart';

class MasterDetail extends StatelessWidget {
  const MasterDetail({
    super.key,
    required this.master,
    required this.detail,
    this.masterWidth = 320,
  });

  final Widget master;
  final Widget detail;
  final double masterWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) =>
          Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
            width: c.maxWidth.isFinite
                ? masterWidth.clamp(0, c.maxWidth * 0.4).toDouble()
                : masterWidth,
            child: master),
        VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
        Expanded(child: detail),
      ]),
    );
  }
}

class MasterPane extends StatelessWidget {
  const MasterPane({
    super.key,
    required this.title,
    this.actions = const [],
    this.search,
    required this.children,
    this.empty,
  });

  final String title;
  final List<Widget> actions;
  final Widget? search;
  final List<Widget> children;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(S.s16, S.s16, S.s12, S.s8),
        child: Row(children: [
          Expanded(
            child: Text(title,
                style: sans(15, weight: W.strong, color: AppColors.fg1)),
          ),
          ...actions,
        ]),
      ),
      if (search != null)
        Padding(
          padding: EdgeInsets.fromLTRB(S.s12, 0, S.s12, S.s8),
          child: search,
        ),
      Expanded(
        child: children.isEmpty && empty != null
            ? Padding(padding: EdgeInsets.all(S.s16), child: empty)
            : ListView(
                padding: EdgeInsets.fromLTRB(S.s8, 0, S.s8, S.s16),
                children: children,
              ),
      ),
    ]);
  }
}

class DetailEmpty extends StatelessWidget {
  const DetailEmpty(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message, style: sans(13, color: AppColors.fg3)),
    );
  }
}

class SettingsBack extends StatelessWidget {
  const SettingsBack(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: S.s4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(PhIcons.caretLeft, size: 16, color: AppColors.fg3),
              SizedBox(width: S.s2),
              Text(label, style: sans(13, color: AppColors.fg3)),
            ]),
          ),
        ),
      ),
    );
  }
}

class SettingsBreadcrumb {
  const SettingsBreadcrumb({
    required this.parent,
    required this.title,
    required this.onBack,
  });

  final String parent;
  final String title;
  final VoidCallback onBack;
}

class SettingsBreadcrumbController extends ChangeNotifier {
  SettingsBreadcrumb? _current;
  Object? _owner;

  SettingsBreadcrumb? get current => _current;

  void set(Object owner, SettingsBreadcrumb crumb) {
    final prev = _current;
    _owner = owner;
    _current = crumb;
    if (prev == null ||
        prev.parent != crumb.parent ||
        prev.title != crumb.title) {
      notifyListeners();
    }
  }

  void clear([Object? owner]) {
    if (owner != null && _owner != owner) return;
    if (_current == null) return;
    _owner = null;
    _current = null;
    notifyListeners();
  }
}

/// Set by the Settings dialog and sheet: they draw the page title, back and
/// close, so page headers and columns inside give that chrome up.
class SettingsChromeScope extends InheritedWidget {
  const SettingsChromeScope({
    super.key,
    this.breadcrumb,
    required super.child,
  });

  final SettingsBreadcrumbController? breadcrumb;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsChromeScope>() != null;

  static SettingsBreadcrumbController? breadcrumbOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SettingsChromeScope>()
          ?.breadcrumb;

  @override
  bool updateShouldNotify(SettingsChromeScope oldWidget) =>
      breadcrumb != oldWidget.breadcrumb;
}

/// Unified desktop nested Settings page: hoists `← Parent / Title` into the
/// modal's single top bar, scrolls the form cleanly, and pins actions in a
/// bottom bar so Save / Cancel / Delete never scroll away.
class SettingsNestedPage extends StatefulWidget {
  const SettingsNestedPage({
    super.key,
    required this.parent,
    required this.title,
    required this.onBack,
    required this.children,
    this.identity,
    this.footerLeft,
    this.footerRight,
  });

  final String parent;
  final String title;
  final VoidCallback onBack;
  final Widget? identity;
  final List<Widget> children;
  final Widget? footerLeft;
  final Widget? footerRight;

  @override
  State<SettingsNestedPage> createState() => _SettingsNestedPageState();
}

class _SettingsNestedPageState extends State<SettingsNestedPage> {
  SettingsBreadcrumbController? _ctrl;

  void _sync() {
    final c = _ctrl;
    if (c == null) return;
    final crumb = SettingsBreadcrumb(
      parent: widget.parent,
      title: widget.title,
      onBack: widget.onBack,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      c.set(this, crumb);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = SettingsChromeScope.breadcrumbOf(context);
    if (next != _ctrl) {
      _ctrl?.clear(this);
      _ctrl = next;
    }
    _sync();
  }

  @override
  void didUpdateWidget(SettingsNestedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parent != widget.parent ||
        oldWidget.title != widget.title ||
        oldWidget.onBack != widget.onBack) {
      _sync();
    }
  }

  @override
  void dispose() {
    final c = _ctrl;
    if (c != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.clear(this));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final hasFooter = widget.footerLeft != null || widget.footerRight != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.identity != null) ...[
                      widget.identity!,
                      Container(
                        margin: const EdgeInsets.only(top: 16, bottom: 20),
                        height: 1,
                        color: AppColors.line,
                      ),
                    ],
                    ...widget.children,
                  ],
                ),
              ),
            ),
          ),
        ),
        if (hasFooter)
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                if (widget.footerLeft != null) widget.footerLeft!,
                const Spacer(),
                if (widget.footerRight != null) widget.footerRight!,
              ],
            ),
          ),
      ],
    );
  }
}

/// Compact identity strip at the top of a nested Settings detail page.
class SettingsIdentityStrip extends StatelessWidget {
  const SettingsIdentityStrip({
    super.key,
    required this.leading,
    required this.title,
    this.badge,
    this.subtitle,
    this.trailing,
  });

  final Widget leading;
  final String title;
  final Widget? badge;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: leading,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(14.5,
                            weight: FontWeight.w600, color: AppColors.fg1)),
                    if (badge != null) badge!,
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(11.5, color: AppColors.fg3)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      );
}

/// Registers a breadcrumb in the Settings dialog's top bar around a custom
/// full-height child (e.g. a split file browser that manages its own scroll).
class SettingsBreadcrumbHost extends StatefulWidget {
  const SettingsBreadcrumbHost({
    super.key,
    required this.parent,
    required this.title,
    required this.onBack,
    required this.child,
  });

  final String parent;
  final String title;
  final VoidCallback onBack;
  final Widget child;

  @override
  State<SettingsBreadcrumbHost> createState() => _SettingsBreadcrumbHostState();
}

class _SettingsBreadcrumbHostState extends State<SettingsBreadcrumbHost> {
  SettingsBreadcrumbController? _ctrl;

  void _sync() {
    final c = _ctrl;
    if (c == null) return;
    final crumb = SettingsBreadcrumb(
      parent: widget.parent,
      title: widget.title,
      onBack: widget.onBack,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      c.set(this, crumb);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = SettingsChromeScope.breadcrumbOf(context);
    if (next != _ctrl) {
      _ctrl?.clear(this);
      _ctrl = next;
    }
    _sync();
  }

  @override
  void didUpdateWidget(SettingsBreadcrumbHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parent != widget.parent ||
        oldWidget.title != widget.title ||
        oldWidget.onBack != widget.onBack) {
      _sync();
    }
  }

  @override
  void dispose() {
    final c = _ctrl;
    if (c != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.clear(this));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SettingsHeader extends StatelessWidget {
  const SettingsHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.back,
    this.compact = false,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? back;
  final bool compact;
  final VoidCallback? onBack;

  /// Inside the overlay a page's own top header keeps only its description
  /// and actions; a sub-view header with its own back stays whole.
  Widget? _hosted(BuildContext context) {
    if (!SettingsChromeScope.of(context) || back != null || onBack != null) {
      return null;
    }
    final sub = subtitle ?? '';
    if (sub.isEmpty && actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Text(sub,
              style: sans(kMobile ? 13 : 12,
                  height: 1.45, color: AppColors.fg3)),
        ),
        for (final a in actions) ...[SizedBox(width: S.s8), a],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hosted = _hosted(context);
    if (hosted != null) return hosted;
    if (compact) {
      // Design language v7: 56 tall, 40 back circle, centred 17/600 title.
      return SizedBox(
        height: Grouped.headerHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Grouped.gutter),
          child: Stack(alignment: Alignment.center, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Grouped.pageTitleStyle(),
              ),
            ),
            Row(children: [
              GroupedCircleButton(
                icon: 'chevron-left',
                tooltip: 'Back',
                onTap: onBack ?? () => Navigator.maybePop(context),
              ),
              const Spacer(),
              ...actions,
            ]),
          ]),
        ),
      );
    }
    return Padding(
      // Desktop: flush with the editorial column, matching section labels below.
      padding: kMobile
          ? const EdgeInsets.fromLTRB(0, 4, 0, 8)
          : const EdgeInsets.fromLTRB(0, 0, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (back != null) ...[back!, SizedBox(height: S.s8)],
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kMobile
                      ? sans(24, weight: FontWeight.w600, color: AppColors.fg1)
                      : sans(16, weight: FontWeight.w500, height: 1.3, color: AppColors.fg1)),
            ),
            for (final a in actions) ...[SizedBox(width: S.s8), a],
          ]),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            SizedBox(height: S.s4),
            Text(subtitle!,
                style: kMobile
                    ? Grouped.subStyle()
                    : sans(12.5, height: 1.45, color: AppColors.fg3)),
          ],
        ],
      ),
    );
  }
}

class SettingsColumn extends StatelessWidget {
  const SettingsColumn({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (SettingsChromeScope.of(context) && !kMobile) {
      // Dialog content pane: 24 side padding, left-aligned (spec D3).
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }
    // One centred column: 680 on phone, one 720 measure on desktop.
    return SingleChildScrollView(
      padding: kMobile
          ? const EdgeInsets.fromLTRB(24, 24, 24, 40)
          : const EdgeInsets.fromLTRB(32, 28, 32, 48),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: kMobile ? Grouped.contentMaxWidth - 48 : 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
