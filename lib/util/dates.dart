import 'package:intl/intl.dart';

final _iso = DateFormat('yyyy-MM-dd');

String iso(DateTime d) => _iso.format(d);
String today() => iso(DateTime.now());
String daysAgo(int n) => iso(DateTime.now().subtract(Duration(days: n)));
String daysAhead(int n) => iso(DateTime.now().add(Duration(days: n)));

/// The day of a date-only API field. Some endpoints send "2026-11-05", others
/// the same column as a timestamp at the server's midnight
/// ("2026-11-04T19:00:00.000Z" on Tashkent time). Adding half a day before
/// reading the UTC date gives the right day either way.
String dayOf(Object? value) {
  if (value == null) return '';
  final text = '$value';
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return text;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text.length >= 10 ? text.substring(0, 10) : text;
  return iso(parsed.toUtc().add(const Duration(hours: 12)));
}

DateTime toDate(Object? value) => DateTime.parse(dayOf(value));

/// "08:30:00" → "08:30"
String hm(Object? time) {
  final text = '${time ?? ''}';
  return text.length >= 5 ? text.substring(0, 5) : text;
}

DateTime mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

/// Dates in the chosen language. Uzbek has no CLDR data in `intl`, so it uses
/// its own month and weekday names.
class Fmt {
  Fmt(this.lang);
  final String lang;

  static const _uzMonths = [
    'yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun',
    'iyul', 'avgust', 'sentabr', 'oktabr', 'noyabr', 'dekabr',
  ];
  static const _uzMonthsShort = [
    'yan', 'fev', 'mar', 'apr', 'may', 'iyn', 'iyl', 'avg', 'sen', 'okt', 'noy', 'dek',
  ];
  static const _uzWeekdays = [
    'Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba', 'Yakshanba',
  ];
  static const _uzWeekdaysShort = ['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'];

  String get _locale => lang == 'en' ? 'en_US' : 'ru';
  DateTime _d(Object value) => value is DateTime ? value : toDate(value);

  /// "13 Nov"
  String day(Object value) {
    final d = _d(value);
    if (lang == 'uz') return '${d.day} ${_uzMonthsShort[d.month - 1]}';
    return DateFormat('d MMM', _locale).format(d).replaceAll('.', '');
  }

  /// "13 Nov 2026"
  String dayYear(Object value) => '${day(value)} ${_d(value).year}';

  /// "Friday, 13 November"
  String dayLong(Object value) {
    final d = _d(value);
    if (lang == 'uz') return '${_uzWeekdays[d.weekday - 1]}, ${d.day} ${_uzMonths[d.month - 1]}';
    return _cap(DateFormat('EEEE, d MMMM', _locale).format(d));
  }

  /// "November 2026"
  String month(DateTime d) {
    if (lang == 'uz') return '${_cap(_uzMonths[d.month - 1])} ${d.year}';
    return _cap(DateFormat('LLLL yyyy', _locale).format(d));
  }

  /// "Mo"
  String weekday(DateTime d) {
    if (lang == 'uz') return _uzWeekdaysShort[d.weekday - 1];
    // intl has no two-letter pattern ("EEEEEE" throws): cut "Mon"/"пн".
    final short = DateFormat('E', _locale).format(d).replaceAll('.', '');
    return _cap(short.length > 2 ? short.substring(0, 2) : short);
  }

  /// "13 Nov, 14:05" for a real moment (created_at).
  String moment(Object value) {
    final d = DateTime.parse('$value').toLocal();
    return '${day(d)}, ${DateFormat('HH:mm').format(d)}';
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
