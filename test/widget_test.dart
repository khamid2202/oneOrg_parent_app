import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:oneorg_parents/l10n/l10n.dart';
import 'package:oneorg_parents/l10n/strings.dart';
import 'package:oneorg_parents/util/dates.dart';

void main() {
  test('every language has every English key', () {
    final en = kStrings['en']!.keys.toSet();
    for (final lang in ['uz', 'ru']) {
      expect(en.difference(kStrings[lang]!.keys.toSet()), isEmpty, reason: lang);
    }
  });

  test('tr fills placeholders and falls back to the key', () {
    expect(tr('en', 'settings.version', {'version': '1.0.0'}), 'Version 1.0.0');
    expect(tr('en', 'no.such.key'), 'no.such.key');
  });

  test('every date format works in every language', () async {
    await initializeDateFormatting('ru');
    await initializeDateFormatting('en_US');
    final d = DateTime(2026, 11, 13, 14, 5);
    for (final lang in ['uz', 'ru', 'en']) {
      final f = Fmt(lang);
      for (final text in [f.day(d), f.dayYear(d), f.dayLong(d), f.month(d), f.weekday(d), f.moment(d.toIso8601String())]) {
        expect(text, isNotEmpty, reason: lang);
      }
    }
    expect(Fmt('en').weekday(d), 'Fr');
    expect(Fmt('ru').weekday(d), 'Пт');
  });

  test('dayOf reads dates and UTC-midnight timestamps', () {
    expect(dayOf('2026-11-05'), '2026-11-05');
    expect(dayOf('2026-11-03T00:00:00.000Z'), '2026-11-03');
    expect(dayOf('2026-11-04T19:00:00.000Z'), '2026-11-05');
  });
}
