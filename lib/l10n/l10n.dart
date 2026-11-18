import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../state/settings.dart';
import 'strings.dart';

const kLanguages = [
  (code: 'uz', label: 'Oʻzbekcha'),
  (code: 'ru', label: 'Русский'),
  (code: 'en', label: 'English'),
];

/// Looks up [key] in the chosen language, falling back to English and then to
/// the key itself. `{{name}}` placeholders are filled from [args]; a `count`
/// arg is filled the same way.
String tr(String lang, String key, [Map<String, Object?> args = const {}]) {
  var text = kStrings[lang]?[key] ?? kStrings['en']?[key] ?? key;
  args.forEach((name, value) {
    text = text.replaceAll('{{$name}}', '${value ?? ''}');
  });
  return text;
}

extension Tr on BuildContext {
  /// `context.t('nav.home')`. Rebuilds when the language changes.
  String t(String key, [Map<String, Object?> args = const {}]) =>
      tr(watch<Settings>().language, key, args);

  String get lang => watch<Settings>().language;
}
