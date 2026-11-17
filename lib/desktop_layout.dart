import 'package:flutter/material.dart';

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
              Icon(Icons.chevron_left, size: 16, color: AppColors.fg3),
              SizedBox(width: S.s2),
              Text(label, style: sans(13, color: AppColors.fg3)),
            ]),
          ),
        ),
      ),
    );
  }
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

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (back != null) ...[back!, SizedBox(height: S.s8)],
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 24 : 18,
                      weight: FontWeight.w600, color: AppColors.fg1)),
            ),
            for (final a in actions) ...[SizedBox(width: S.s8), a],
          ]),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            SizedBox(height: S.s4),
            Text(subtitle!, style: Grouped.subStyle()),
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
    // Design language v7: one centred column, 680 wide with its padding.
    // Desktop sits at the top left of the dialog page; centring left wide gutters.
    return SingleChildScrollView(
      padding: kMobile
          ? const EdgeInsets.fromLTRB(24, 24, 24, 40)
          : const EdgeInsets.fromLTRB(28, 18, 28, 32),
      child: Align(
        alignment: kMobile ? Alignment.topCenter : Alignment.topLeft,
        child: ConstrainedBox(
          // The dialog bounds desktop; only the phone caps the column.
          constraints: BoxConstraints(
              maxWidth:
                  kMobile ? Grouped.contentMaxWidth - 48 : double.infinity),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
