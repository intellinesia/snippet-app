import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Release spring for drags: close to critically damped, a hint of bounce.
const SpringDescription gestureSpring =
    SpringDescription(mass: 1, stiffness: 420, damping: 36);

/// Past the edge a drag moves a diminishing fraction of the finger's travel.
/// [dim] is the distance at which the band saturates.
double rubberBand(double x, double dim, [double c = 0.55]) {
  if (x == 0) return 0;
  final a = x.abs();
  final r = (1 - 1 / (a * c / dim + 1)) * dim;
  return x < 0 ? -r : r;
}

/// A drag dismisses on enough distance OR a fast enough flick in the dismiss
/// direction. [velocity] is signed along the dismiss direction.
bool dragDismisses(
        {required double distance,
        required double velocity,
        required double distanceThreshold,
        required double velocityThreshold}) =>
    distance > distanceThreshold || velocity > velocityThreshold;

/// Carries [c] from its current value to [to], leaving at [velocity] units/s.
TickerFuture springTo(AnimationController c, double to, double velocity,
    {SpringDescription spring = gestureSpring, double epsilon = 0.5}) {
  return c.animateWith(SpringSimulation(spring, c.value, to, velocity,
      snapToEnd: true, tolerance: Tolerance(distance: epsilon, velocity: epsilon * 10)));
}
