import 'dart:async';

import 'package:flutter/material.dart';

import '../app_popover.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'desktop_composer.dart';

/// Desktop CMP-15 plus menu. The composer owns this menu instead of the phone
/// attachment sheet: photo, file, voice note, then a blank canvas.
class DeskComposerPlusButton extends StatelessWidget {
  const DeskComposerPlusButton({
    super.key,
    required this.onPhoto,
    required this.onFile,
    required this.onVoice,
    required this.onCanvas,
  });

  final VoidCallback onPhoto;
  final VoidCallback onFile;
  final VoidCallback onVoice;
  final VoidCallback onCanvas;

  PopupMenuEntry<String> _item(String value, String icon, String label) =>
      AppMenuItem<String>(
        value: value,
        height: 28,
        padding: EdgeInsets.zero,
        searchText: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(children: [
            AppIcon(icon, size: 14, color: AppColors.fg2),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12,
                      weight: FontWeight.w500,
                      height: 17 / 12,
                      color: AppColors.fg1)),
            ),
          ]),
        ),
      );

  Future<void> _open(BuildContext anchor) async {
    final choice = await showAppMenu<String>(
      anchor,
      anchor: anchor,
      minWidth: 168,
      maxWidth: 190,
      items: [
        _item('photo', 'image', 'Photo'),
        _item('file', 'file', 'File'),
        if (kCanRecord) _item('voice', 'mic', 'Voice'),
        _item('canvas', 'canvas', 'Canvas'),
      ],
    );
    switch (choice) {
      case 'photo':
        onPhoto();
      case 'file':
        onFile();
      case 'voice':
        onVoice();
      case 'canvas':
        onCanvas();
    }
  }

  @override
  Widget build(BuildContext context) => Builder(
        builder: (anchor) => DeskIconButton('plus',
            tooltip: 'Add',
            iconSize: 12,
            color: AppColors.fg3,
            onTap: () => unawaited(_open(anchor))),
      );
}
