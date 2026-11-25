import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/parent_api.dart';
import '../l10n/l10n.dart';
import '../state/children.dart';
import '../state/push.dart';
import '../state/query_cache.dart';
import '../widgets/common.dart';
import '../widgets/states.dart';
import '../widgets/theme.dart';
import 'attendance_screen.dart';
import 'grades_screen.dart';
import 'home_screen.dart';
import 'more_screens.dart';
import 'schedule_screen.dart';

/// Unread notifications over all children, for the bell.
class Unread extends ChangeNotifier {
  Unread(this._api);
  final ParentApi _api;
  int count = 0;
  Timer? _timer;

  void start(List<Child> children) {
    _timer?.cancel();
    refresh(children);
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => refresh(children),
    );
  }

  Future<void> refresh(List<Child> children) async {
    final counts = await Future.wait(
      children.map(
        (c) => _api
            .unreadCount(c.id)
            .then((r) => (r['unread_count'] as num?)?.toInt() ?? 0)
            .catchError((Object _) => 0),
      ),
    );
    count = counts.fold(0, (a, b) => a + b);
    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    count = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  /// Asks the open shell to show a tab (2 = grades, 3 = attendance), for pages
  /// pushed over it, such as the inbox, that link to a tab.
  static final tabRequest = ValueNotifier<int?>(null);

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  late final Push _push = context.read<Push>();

  @override
  void initState() {
    super.initState();
    final children = context.read<Children>();
    _push.onMessage = _onPush;
    Shell.tabRequest.addListener(_onTabRequest);
    children.load().then((_) {
      if (!mounted) return;
      context.read<Unread>().start(children.list);
      _push.enableFor([for (final c in children.list) c.id]);
      // Only now can a tapped push pick its child; one that came earlier waited.
      _push.onOpen = _openFromPush;
      _push.takePendingOpen(_openFromPush);
    });
  }

  @override
  void dispose() {
    Shell.tabRequest.removeListener(_onTabRequest);
    _push
      ..onOpen = null
      ..onMessage = null;
    super.dispose();
  }

  void _onTabRequest() {
    final tab = Shell.tabRequest.value;
    if (tab == null || !mounted) return;
    Shell.tabRequest.value = null;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _goTo(tab);
  }

  /// A push was tapped: switch to that child and show their notifications.
  void _openFromPush(int? personId) {
    if (!mounted) return;
    final children = context.read<Children>();
    if (personId != null && children.list.any((c) => c.id == personId)) {
      children.select(personId);
    }
    _onPush(personId);
    Navigator.of(context).popUntil((r) => r.isFirst);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
  }

  /// A push arrived: the bell and that child's inbox are out of date.
  void _onPush(int? personId) {
    if (!mounted) return;
    final children = context.read<Children>().list;
    context.read<Unread>().refresh(children);
    // The inbox holds every child's notifications, so any push makes it stale.
    context.read<QueryCache>().remove(NotificationsScreen.cacheKey);
  }

  void _goTo(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final children = context.watch<Children>();
    final child = children.child;

    Widget body;
    if (children.loading) {
      body = const LoadingState();
    } else if (children.error != null && children.list.isEmpty) {
      body = ErrorState(error: children.error, onRetry: children.load);
    } else if (child == null) {
      body = EmptyState(
        text: context.t('children.none'),
        icon: Icons.family_restroom,
      );
    } else {
      body = IndexedStack(
        index: _tab,
        children: [
          HomeScreen(onOpen: _goTo),
          const ScheduleScreen(),
          const GradesScreen(),
          const AttendanceScreen(),
          const SettingsScreen(inTab: true),
        ],
      );
    }

    final tabs = [
      (Icons.home_outlined, Icons.home, 'nav.home'),
      (Icons.calendar_month_outlined, Icons.calendar_month, 'nav.schedule'),
      (Icons.star_outline, Icons.star, 'nav.grades'),
      (Icons.event_available_outlined, Icons.event_available, 'nav.attendance'),
      (Icons.settings_outlined, Icons.settings, 'nav.settings'),
    ];

    return PopScope(
      // Back on an inner tab goes Home; only Home closes the app.
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goTo(0);
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          toolbarHeight: 60,
          title: const ChildSwitcher(),
          actions: const [BellButton(), SizedBox(width: 8)],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, thickness: 1, color: context.c.line),
          ),
        ),
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _goTo,
          destinations: [
            for (final (icon, selected, key) in tabs)
              NavigationDestination(
                icon: Icon(icon),
                selectedIcon: Icon(selected),
                label: context.t(key),
              ),
          ],
        ),
      ),
    );
  }
}

class BellButton extends StatelessWidget {
  const BellButton({super.key});
  @override
  Widget build(BuildContext context) {
    final unread = context.watch<Unread>().count;
    return IconButton(
      tooltip: context.t('nav.notifications'),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
      ),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_none),
      ),
    );
  }
}

/// The open child's name and class. With more than one child, a switch
/// button moves to the next child, wrapping round after the last.
class ChildSwitcher extends StatelessWidget {
  const ChildSwitcher({super.key});
  @override
  Widget build(BuildContext context) {
    final children = context.watch<Children>();
    final child = children.child;
    if (child == null) return const SizedBox.shrink();
    final list = children.list;

    final current = Row(
      children: [
        Expanded(
          // A ticker: the next child rolls up from below, the old one leaves upward.
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 550),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, ?current],
              ),
              transitionBuilder: (widget, animation) {
                // The leaving child's animation runs 1 → 0, so its tween starts
                // above: it slides from 0 up to -1 as it goes.
                final incoming = widget.key == ValueKey(child.id);
                final offset = Tween<Offset>(
                  begin: incoming ? const Offset(0, 1) : const Offset(0, -1),
                  end: Offset.zero,
                ).animate(animation);
                return SlideTransition(
                  position: offset,
                  child: FadeTransition(opacity: animation, child: widget),
                );
              },
              child: Row(
                key: ValueKey(child.id),
                children: [
                  Avatar(name: child.fullName, url: child.picture, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          child.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (child.className.isNotEmpty)
                          Text(
                            child.className,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.c.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (list.length > 1) ...[
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down, color: context.c.accent),
        ],
      ],
    );
    if (list.length < 2) return current;

    // Tapping the child opens a list of all children to pick from.
    return PopupMenuButton<int>(
      tooltip: context.t('children.switch'),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: children.select,
      itemBuilder: (_) => [
        for (final c in list)
          PopupMenuItem<int>(
            value: c.id,
            child: Row(
              children: [
                Avatar(name: c.fullName, url: c.picture, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      if (c.className.isNotEmpty)
                        Text(c.className, style: TextStyle(fontSize: 12, color: context.c.muted)),
                    ],
                  ),
                ),
                if (c.id == child.id) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check, size: 20, color: context.c.accent),
                ],
              ],
            ),
          ),
      ],
      child: current,
    );
  }
}
