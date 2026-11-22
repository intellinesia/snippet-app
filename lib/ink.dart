import 'package:flutter/painting.dart';

const Color _darkInk = Color(0xFF14141A);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Text colour for a [fill]: whichever of dark ink and white contrasts more.
Color inkOn(Color fill) =>
    _contrast(_darkInk, fill) >= _contrast(const Color(0xFFFFFFFF), fill)
        ? _darkInk
        : const Color(0xFFFFFFFF);

double inkContrast(Color fill) => _contrast(inkOn(fill), fill);
