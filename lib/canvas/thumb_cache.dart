import 'dart:collection';

/// Supported thumbnail scale buckets requested from `/canvas/frames/{id}/thumb.png?scale=`.
const List<double> kCanvasThumbScales = <double>[0.25, 0.5, 1.0, 2.0];

/// Chooses the appropriate thumbnail scale bucket for the current [zoom] and [devicePixelRatio].
double pickThumbScaleBucket(double zoom, {double devicePixelRatio = 1.0}) {
  final effective = zoom * devicePixelRatio;
  if (effective <= 0.30) return 0.25;
  if (effective <= 0.65) return 0.5;
  if (effective <= 1.35) return 1.0;
  return 2.0;
}

/// Cache key identifying a frame thumbnail at a specific revision and scale bucket.
class ThumbCacheKey {
  const ThumbCacheKey({
    required this.frameId,
    required this.rev,
    required this.scale,
  });

  final String frameId;
  final int rev;
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is ThumbCacheKey &&
      other.frameId == frameId &&
      other.rev == rev &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(frameId, rev, scale);

  @override
  String toString() => 'ThumbCacheKey($frameId@$rev@${scale}x)';
}

class _CacheEntry<T> {
  _CacheEntry(this.value, this.bytes);
  final T value;
  final int bytes;
}

/// Byte-budgeted LRU cache for decoded frame thumbnails.
class ThumbLruCache<T> {
  ThumbLruCache({
    required this.maxBytes,
    this.onEvict,
  }) : assert(maxBytes > 0);

  static const int desktopBudgetBytes = 80 * 1024 * 1024;
  static const int phoneBudgetBytes = 40 * 1024 * 1024;

  final int maxBytes;
  final void Function(ThumbCacheKey key, T value)? onEvict;

  final LinkedHashMap<ThumbCacheKey, _CacheEntry<T>> _entries =
      LinkedHashMap<ThumbCacheKey, _CacheEntry<T>>();

  int _currentBytes = 0;
  int _evictionCount = 0;

  int get currentBytes => _currentBytes;
  int get length => _entries.length;
  int get evictionCount => _evictionCount;

  bool containsKey(ThumbCacheKey key) => _entries.containsKey(key);

  /// Fetches [key] and marks it most-recently used.
  T? get(ThumbCacheKey key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    return entry.value;
  }

  /// Peeks without altering LRU order.
  T? peek(ThumbCacheKey key) => _entries[key]?.value;

  /// Inserts or replaces [key] with [bytes] footprint, evicting LRU entries over budget.
  void put(ThumbCacheKey key, T value, int bytes) {
    final safeBytes = bytes < 0 ? 0 : bytes;
    final existing = _entries.remove(key);
    if (existing != null) {
      _currentBytes -= existing.bytes;
      if (!identical(existing.value, value)) {
        onEvict?.call(key, existing.value);
      }
    }

    // Drop oversized items before evicting so a single huge image cannot wipe the cache.
    if (safeBytes > maxBytes) {
      onEvict?.call(key, value);
      return;
    }

    while (_entries.isNotEmpty && _currentBytes + safeBytes > maxBytes) {
      final oldestKey = _entries.keys.first;
      final removed = _entries.remove(oldestKey)!;
      _currentBytes -= removed.bytes;
      _evictionCount++;
      onEvict?.call(oldestKey, removed.value);
    }

    _entries[key] = _CacheEntry<T>(value, safeBytes);
    _currentBytes += safeBytes;
  }

  /// Returns the closest cached thumbnail for [frameId], preferring matching [rev] then closest scale.
  T? bestAvailable(String frameId, {required int rev, required double preferredScale}) {
    final exact = get(ThumbCacheKey(frameId: frameId, rev: rev, scale: preferredScale));
    if (exact != null) return exact;

    ThumbCacheKey? bestKey;
    for (final key in _entries.keys) {
      if (key.frameId != frameId) continue;
      if (bestKey == null || _isBetterFallback(key, bestKey, rev, preferredScale)) {
        bestKey = key;
      }
    }
    return bestKey != null ? _entries[bestKey]?.value : null;
  }

  static bool _isBetterFallback(
    ThumbCacheKey candidate,
    ThumbCacheKey current,
    int targetRev,
    double preferredScale,
  ) {
    final candExactRev = candidate.rev == targetRev;
    final currExactRev = current.rev == targetRev;
    if (candExactRev != currExactRev) return candExactRev;
    if (!candExactRev && candidate.rev != current.rev) {
      return candidate.rev > current.rev;
    }
    final candDiff = (candidate.scale - preferredScale).abs();
    final currDiff = (current.scale - preferredScale).abs();
    if ((candDiff - currDiff).abs() > 1e-6) return candDiff < currDiff;
    return candidate.scale > current.scale;
  }

  /// Removes all cached scales for [frameId] except optionally keeping [keepRev].
  void invalidateFrame(String frameId, {int? keepRev}) {
    final toRemove = <ThumbCacheKey>[
      for (final k in _entries.keys)
        if (k.frameId == frameId && (keepRev == null || k.rev != keepRev)) k,
    ];
    for (final key in toRemove) {
      final removed = _entries.remove(key)!;
      _currentBytes -= removed.bytes;
      onEvict?.call(key, removed.value);
    }
  }

  void clear() {
    final items = _entries.entries.toList(growable: false);
    _entries.clear();
    _currentBytes = 0;
    for (final item in items) {
      onEvict?.call(item.key, item.value.value);
    }
  }
}
