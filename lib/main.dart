import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'api/parent_api.dart';
import 'api/storage.dart';
import 'screens/auth_screens.dart';
import 'screens/shell.dart';
import 'state/auth.dart';
import 'state/children.dart';
import 'state/push.dart';
import 'state/query_cache.dart';
import 'state/settings.dart';
import 'widgets/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([initializeDateFormatting('ru'), initializeDateFormatting('en_US')]);
  final storage = await Storage.open();
  final api = ParentApi(ApiClient(storage));
  final cache = QueryCache();
  final push = Push(api);
  final auth = Auth(api, storage, cache)
    // Unregister while the session can still authorize the request.
    ..beforeLogout = push.disable;

  runApp(MultiProvider(
    providers: [
      Provider.value(value: storage),
      Provider.value(value: api),
      Provider.value(value: cache),
      ChangeNotifierProvider(create: (_) => Settings(storage)),
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: push),
      ChangeNotifierProvider(create: (_) => Children(api, storage)),
      ChangeNotifierProvider(create: (_) => Unread(api)),
    ],
    child: const ParentsApp(),
  ));
  // After runApp so a slow or missing Firebase never delays the first frame.
  push.initialize();
}

class ParentsApp extends StatelessWidget {
  const ParentsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    return MaterialApp(
      title: 'Dombit Parents',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      // The app's own text comes from l10n/strings.dart; this sets the
      // language of system widgets (date pickers, text selection menus).
      locale: Locale(settings.language),
      supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _Root(),
    );
  }
}

/// Login, or the app.
class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool? _wasLoggedIn;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<Auth>();
    if (_wasLoggedIn == true && !auth.loggedIn) {
      // Logged out (or the token expired): forget this family.
      context.read<Children>().reset();
      context.read<Unread>().stop();
    }
    _wasLoggedIn = auth.loggedIn;
    if (!auth.loggedIn) return const LoginScreen();
    if (auth.offerPasskey) return const PasskeyOfferScreen();
    return const Shell();
  }
}
