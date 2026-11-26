import 'package:flutter/material.dart';

import '../theme.dart';

/// v19 unread marker: a quiet centred label in a hairline, 28 high.
class UnreadDivider extends StatelessWidget {
  const UnreadDivider({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 28,
        child: Row(children: [
          Expanded(child: Container(height: 1, color: AppColors.surface3)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('Unread',
                style: sans(11,
                    height: 15 / 11,
                    weight: FontWeight.w500,
                    color: AppColors.fg3)),
          ),
          Expanded(child: Container(height: 1, color: AppColors.surface3)),
        ]),
      );
}
