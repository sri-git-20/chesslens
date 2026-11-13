import 'dart:math' as math;

/// One Euro filter for low-latency smoothing of a noisy 1D signal sampled at an
/// irregular rate.
///
/// It adapts its cutoff frequency to the signal's speed: heavy smoothing (low
/// cutoff) when the value changes slowly, and low lag (high cutoff) when it
/// changes quickly. This makes it well suited to smoothing per-frame landmark
/// coordinates without introducing visible lag during fast motion.
///
/// Tune with [minCutoff] (raise to reduce jitter at rest) and [beta] (raise to
/// reduce lag during fast motion). See https://gery.casiez.net/1euro/.
class OneEuroFilter {
  /// Minimum cutoff frequency; the floor on smoothing when the signal is slow.
  final double minCutoff;

  /// Speed coefficient; how aggressively the cutoff rises with signal speed.
  final double beta;

  /// Cutoff frequency used to smooth the derivative estimate.
  final double dCutoff;

  double? _xPrev;
  double _dxPrev = 0.0;
  double? _tPrev;

  OneEuroFilter({this.minCutoff = 1.0, this.beta = 0.1, this.dCutoff = 1.0});

  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  /// Filters sample [x] taken at time [tSec] (seconds) and returns the smoothed
  /// value. The first sample is returned unchanged.
  double filter(double x, double tSec) {
    if (_xPrev == null || _tPrev == null) {
      _xPrev = x;
      _tPrev = tSec;
      _dxPrev = 0.0;
      return x;
    }
    final dt = (tSec - _tPrev!).clamp(1e-6, 1.0);
    final dx = (x - _xPrev!) / dt;
    final aD = _alpha(dCutoff, dt);
    final dxHat = aD * dx + (1 - aD) * _dxPrev;
    final cutoff = minCutoff + beta * dxHat.abs();
    final a = _alpha(cutoff, dt);
    final xHat = a * x + (1 - a) * _xPrev!;
    _xPrev = xHat;
    _dxPrev = dxHat;
    _tPrev = tSec;
    return xHat;
  }

  /// Clears the filter's history so the next sample is returned unchanged.
  void reset() {
    _xPrev = null;
    _tPrev = null;
    _dxPrev = 0.0;
  }
}
