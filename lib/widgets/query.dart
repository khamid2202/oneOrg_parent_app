import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/query_cache.dart';
import 'states.dart';

/// The state of one load, for [Query.builder].
class Snap<T> {
  const Snap({this.data, this.error, this.loading = false, this.refreshing = false, required this.reload});
  final T? data;
  final Object? error;
  /// First load, nothing to show yet.
  final bool loading;
  /// Reloading while the last data is shown.
  final bool refreshing;
  final Future<void> Function() reload;
}

/// Loads [load] under [cacheKey] (null waits) and rebuilds with a [Snap].
/// The last answer for the key shows at once while it refreshes.
class Query<T> extends StatefulWidget {
  const Query({super.key, required this.cacheKey, required this.load, required this.builder});

  final String? cacheKey;
  final Future<T> Function() load;
  final Widget Function(BuildContext context, Snap<T> snap) builder;

  @override
  State<Query<T>> createState() => _QueryState<T>();
}

class _QueryState<T> extends State<Query<T>> {
  Object? _error;
  bool _running = false;
  String? _key;

  QueryCache get _cache => context.read<QueryCache>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void didUpdateWidget(covariant Query<T> old) {
    super.didUpdateWidget(old);
    if (old.cacheKey != widget.cacheKey) _reload();
  }

  Future<void> _reload() async {
    final key = widget.cacheKey;
    if (key == null || !mounted) return;
    setState(() {
      _key = key;
      _error = null;
      _running = true;
    });
    try {
      await _cache.fetch<T>(key, widget.load);
      if (mounted && _key == key) setState(() => _running = false);
    } catch (e) {
      if (mounted && _key == key) {
        setState(() {
          _error = e;
          _running = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.cacheKey;
    final current = _key == key;
    final has = key != null && _cache.has(key);
    final data = has ? _cache.peek<T>(key) : null;
    return widget.builder(
      context,
      Snap<T>(
        data: data,
        error: current ? _error : null,
        loading: key != null && !has && (!current || _running || _error == null),
        refreshing: current && _running && has,
        reload: _reload,
      ),
    );
  }
}

/// [Query] with the usual loading, error and empty states.
class QueryView<T> extends StatelessWidget {
  const QueryView({
    super.key,
    required this.cacheKey,
    required this.load,
    required this.builder,
    this.isEmpty,
    this.emptyText,
  });

  final String? cacheKey;
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Snap<T> snap) builder;
  final bool Function(T data)? isEmpty;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    return Query<T>(
      cacheKey: cacheKey,
      load: load,
      builder: (context, snap) {
        if (snap.loading) return const LoadingState();
        final data = snap.data;
        if (data == null) return ErrorState(error: snap.error, onRetry: snap.reload);
        if (isEmpty?.call(data) ?? false) return EmptyState(text: emptyText ?? '');
        return builder(context, data, snap);
      },
    );
  }
}
