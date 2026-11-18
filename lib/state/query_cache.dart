import 'dart:async';

/// Last answer per key, so a screen opened again shows its data at once and
/// refreshes in the background. Two widgets asking for the same key at the
/// same time share one request.
class QueryCache {
  final _data = <String, Object?>{};
  final _inflight = <String, Future<Object?>>{};

  bool has(String key) => _data.containsKey(key);
  T? peek<T>(String key) => _data[key] as T?;

  Future<T> fetch<T>(String key, Future<T> Function() load) {
    final running = _inflight[key];
    if (running != null) return running.then((value) => value as T);
    final future = load().then((value) {
      _data[key] = value;
      return value;
    });
    _inflight[key] = future;
    future.whenComplete(() => _inflight.remove(key)).ignore();
    return future;
  }

  void put(String key, Object? value) => _data[key] = value;
  void remove(String key) => _data.remove(key);
  void clear() {
    _data.clear();
    _inflight.clear();
  }
}
