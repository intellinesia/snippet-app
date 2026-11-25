import 'package:flutter/foundation.dart';

/// Total needs-you count across agents, published by the daemon client each
/// time the agents list loads (the agents payload carries `needs_you`).
final ValueNotifier<int> phoneNeedsYou = ValueNotifier(0);

/// Opens the needs-you list; set by the shell that owns the attention
/// destination.
VoidCallback? onReviewNeedsYou;
