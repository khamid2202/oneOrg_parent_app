import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../util/dates.dart';

/// Sample data for working on screens without the API
/// (`--dart-define=MOCK=true`). Shapes follow oneorg-backend/docs/parent/*.md.
/// Any login works. Ported from the web app's src/api/mock.js.
class MockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final body = options.data is Map ? (options.data as Map).cast<String, dynamic>() : <String, dynamic>{};
    final data = _route(options.method.toLowerCase(), options.path, options.queryParameters, body);
    return ResponseBody.fromString(
      jsonEncode(data ?? {'message': 'No mock for ${options.method} ${options.path}'}),
      data == null ? 404 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _d(int offset) => daysAhead(offset);
int _weekday(String date) => DateTime.parse(date).weekday % 7; // Sunday = 0, like JS

const _subjects = [
  (1, 'Mathematics', 'Jane Doe'),
  (2, 'Physics', 'Rustam Karimov'),
  (3, 'English', 'Emily Stone'),
  (4, 'History', 'Dilnoza Yusupova'),
  (5, 'Biology', 'Aziz Rahimov'),
  (6, 'Literature', 'Nodira Saidova'),
];
const _times = ['08:30', '09:25', '10:20', '11:25', '12:20', '13:40'];

final _persons = [
  {
    'id': 100,
    'la_id': 'DIS260001',
    'full_name': 'Valiyev Ali Olimovich',
    'picture': null,
    'groups': [
      {'student_id': 77, 'id': 14, 'join_date': '2026-09-01', 'leave_date': null, 'status': 'studying',
        'name': 'Grade 7 - A', 'class_pair_compact': '7A', 'teacher_name': 'Jane Doe'},
    ],
  },
  {
    'id': 101,
    'la_id': 'DIS260002',
    'full_name': 'Valiyeva Madina Olimovna',
    'picture': null,
    'groups': [
      {'student_id': 91, 'id': 5, 'join_date': '2026-09-01', 'leave_date': null, 'status': 'studying',
        'name': 'Grade 3 - B', 'class_pair_compact': '3B', 'teacher_name': 'Nodira Saidova'},
    ],
  },
];

List<Map<String, dynamic>> _lessons(int personId, String date) {
  final day = _weekday(date);
  if (day == 0) return [];
  final count = personId == 101 ? 4 : 6;
  return [
    for (var i = 0; i < count; i++)
      () {
        final s = _subjects[(i + day + personId) % _subjects.length];
        final parts = _times[i].split(':').map(int.parse).toList();
        final endMin = parts[0] * 60 + parts[1] + 45;
        final end = '${(endMin ~/ 60).toString().padLeft(2, '0')}:${(endMin % 60).toString().padLeft(2, '0')}';
        final lesson = <String, dynamic>{
          'id': day * 10 + i, 'lesson_type': 'structured', 'text': null, 'room': '${201 + i}',
          'start_time': '${_times[i]}:00', 'end_time': '$end:00',
          'subject_id': s.$1, 'subject': s.$2, 'teacher': s.$3, 'status': 'scheduled', 'substitution': null,
        };
        if (personId == 100 && i == 2 && date == _d(0)) {
          lesson['status'] = 'substituted';
          lesson['substitution'] = {'type': 'cover', 'substitute_teacher': 'Aziz Rahimov', 'note': null};
        }
        if (personId == 100 && i == 5 && date == _d(0)) {
          lesson['status'] = 'cancelled';
          lesson['substitution'] = {'type': 'cancel', 'substitute_teacher': null, 'note': 'Teacher is at a seminar'};
        }
        return lesson;
      }(),
  ];
}

bool _inRange(String date, Map<String, dynamic> q) =>
    (q['start_date'] == null || date.compareTo('${q['start_date']}') >= 0) &&
    (q['end_date'] == null || date.compareTo('${q['end_date']}') <= 0);

int _limit(Map<String, dynamic> q, int fallback) => int.tryParse('${q['limit'] ?? ''}') ?? fallback;

Map<String, dynamic> _attendance(int personId, Map<String, dynamic> q) {
  final rows = <Map<String, dynamic>>[];
  for (var offset = 0; offset > -70; offset--) {
    final date = _d(offset);
    if (_weekday(date) == 0) continue;
    var status = 'present';
    String? reason;
    final n = (-offset + personId) % 17;
    if (n == 5) (status, reason) = ('late', 'Came after first period');
    if (n == 11) status = 'absent';
    if (n == 14) (status, reason) = ('excused', "Doctor's appointment");
    rows.add({'id': 4000 - offset + personId, 'person_id': personId, 'status': status, 'reason': reason, 'date': date});
  }
  final filtered = rows.where((r) => (q['date'] == null || r['date'] == q['date']) && _inRange(r['date'], q)).toList();
  return {'ok': true, 'meta': {'total': filtered.length}, 'attendance': filtered.take(_limit(q, 20)).toList()};
}

Map<String, dynamic> _grades(int personId, Map<String, dynamic> q) {
  final rows = <Map<String, dynamic>>[];
  for (var offset = 0; offset > -90; offset--) {
    final date = _d(offset);
    final ls = _lessons(personId, date).take(3).toList();
    for (var i = 0; i < ls.length; i++) {
      final seed = (-offset * 7 + i * 13 + personId) % 23;
      // Grading v2: late deducts, five categories 20/10/30/20/20.
      final parts = <int?>[0, seed % 4 == 0 ? 10 : 20, seed % 6 != 0 ? 10 : 5, 15 + seed % 16, 8 + seed % 13, seed % 5 != 0 ? 15 : null];
      final low = seed == 9;
      final status = switch (seed) { 4 || 15 => 'late', 11 => 'absent', 19 => 'excused', _ => 'present' };
      final away = status == 'absent' || status == 'excused';
      // Lessons over two weeks old were graded before v2: attendance is a
      // category of 20 (16 when late), homework one number out of 20.
      final v1 = offset < -14;
      final late = v1 ? (away ? 0 : status == 'late' ? 16 : 20) : (status == 'late' ? -4 : 0);
      if (v1) {
        parts[2] = null;
        parts[3] = parts[3]! * 2 ~/ 3;
      }
      final total = away ? 0 : low ? 30 : (parts.fold<int>(late, (s, v) => s + (v ?? 0))).clamp(0, 100);
      final madeUp = low && offset < -3;
      rows.add({
        'lesson_instance_id': 50000 - offset * 10 + i, 'date': date, 'subject_id': ls[i]['subject_id'],
        'start_time': ls[i]['start_time'],
        'subject': ls[i]['subject'], 'attendance_status': status,
        'minutes_late': status == 'late' ? 4 + seed % 12 : null,
        'attendance_score': late, 'grading_version': v1 ? 1 : 2,
        'materials_score': parts[1], 'homework_done_score': parts[2], 'homework_score': parts[3],
        'activity_score': parts[4], 'notes_score': parts[5], 'total': total, 'makeup_score': madeUp ? 72 : null,
        'makeup_at': madeUp ? '${_d(offset + 3)}T10:00:00.000Z' : null, 'is_made_up': madeUp,
        'score': madeUp ? 72 : total, 'comment': low ? 'Did not bring homework, was distracted.' : null,
      });
    }
  }
  final subject = int.tryParse('${q['subject_id'] ?? ''}');
  final filtered = rows.where((r) => _inRange(r['date'], q) && (subject == null || r['subject_id'] == subject)).toList();
  double avg(String key) =>
      filtered.fold<num>(0, (s, r) => s + ((r[key] as num?) ?? 0)) / (filtered.isEmpty ? 1 : filtered.length);
  // Category averages count v2 lessons only, null when there are none (as the API does).
  final v2 = filtered.where((r) => r['grading_version'] == 2).toList();
  double? catAvg(String key) =>
      v2.isEmpty ? null : v2.fold<num>(0, (s, r) => s + ((r[key] as num?) ?? 0)) / v2.length;
  return {
    'ok': true,
    'meta': {
      'total': filtered.length,
      'summary': {
        'lessons': filtered.length, 'average_score': avg('score'), 'average_total': avg('total'),
        'average_attendance': catAvg('attendance_score'), 'average_materials': catAvg('materials_score'),
        'average_homework_done': catAvg('homework_done_score'), 'average_homework': catAvg('homework_score'),
        'average_activity': catAvg('activity_score'), 'average_notes': catAvg('notes_score'), 'made_up': filtered.where((r) => r['is_made_up'] == true).length,
      },
    },
    'result': filtered.take(_limit(q, 50)).toList(),
  };
}

List<Map<String, dynamic>> _pointRows(int personId) => [
      for (var i = 0; i < 42; i++)
        {
          'id': 900 + i, 'person_id': personId, 'subject_id': _subjects[i % 6].$1,
          'subject_name': _subjects[i % 6].$2, 'teacher_name': _subjects[i % 6].$3,
          'points': i % 9 == 4 ? -2 : 1 + i % 5,
          'reason': ['Homework', 'Active in class', 'Olympiad', null][i % 4],
          'date': _d(-i * 2),
        },
    ];

const _classmates = ['Akmal Ergashev', 'Vali Aliyev', 'Zarina Tosheva', 'Bobur Nazarov', 'Sevara Islomova'];

final _examList = () {
  final periods = [('Term 1 Finals', _d(-20), [1, 2, 3, 4]), ('October monthly', _d(-45), [1, 3]), ('Term 2 Finals', _d(25), [1, 2])];
  return [
    for (var p = 0; p < periods.length; p++)
      for (var i = 0; i < periods[p].$3.length; i++)
        () {
          final sid = periods[p].$3[i];
          final past = periods[p].$2.compareTo(_d(0)) < 0;
          final score = past ? 62 + (sid * 11 + p * 7) % 35 : null;
          return <String, dynamic>{
            'id': p * 10 + i + 1, 'exam_period_id': p + 1, 'exam_period_name': periods[p].$1,
            'exam_period_date': periods[p].$2, 'subject_id': sid, 'subject_name': _subjects[sid - 1].$2,
            'max_score': 100, 'current_result_id': past ? 300 + i : null, 'current_score': score,
            'current_percentage': score,
          };
        }(),
  ];
}();

var _notifications = <Map<String, dynamic>>[
  {'id': 3, 'title': 'Exam results published', 'body': 'Term 1 Finals results are now available.', 'is_read': false,
    'created_at': DateTime.now().toUtc().toIso8601String()},
  {'id': 2, 'title': 'Parent meeting', 'body': 'Friday at 17:00 in room 204.', 'is_read': false,
    'created_at': '${_d(-1)}T09:00:00.000Z'},
  {'id': 1, 'title': 'Welcome', 'body': "You can now follow your child's school day here.", 'is_read': true,
    'created_at': '${_d(-9)}T09:00:00.000Z'},
];

List<Map<String, dynamic>> _ranked(List<Map<String, dynamic>> rows, String by) {
  rows.sort((a, b) => (b[by] as num).compareTo(a[by] as num));
  return [for (var i = 0; i < rows.length; i++) {'is_current_student': false, 'picture': null, ...rows[i], 'rank': i + 1}];
}

Map<String, dynamic>? _route(String method, String url, Map<String, dynamic> q, Map<String, dynamic> body) {
  final personId = int.tryParse('${q['person_id'] ?? ''}') ?? 0;
  final me = _persons.where((p) => p['id'] == personId).firstOrNull;
  if (url.startsWith('/parent/auth/login/')) {
    return {'ok': true, 'result': {'token': 'mock-token'}};
  }
  if (url.startsWith('/parent/auth/')) return {'ok': true};
  if (url == '/parent/persons/accessible') return {'ok': true, 'result': {'persons': _persons}};
  if (url == '/parent/schedule/today-lessons') return {'ok': true, 'result': {'date': _d(0), 'lessons': _lessons(personId, _d(0))}};
  if (url == '/parent/schedule') return {'ok': true, 'result': {'date': q['date'], 'lessons': _lessons(personId, '${q['date']}')}};
  if (url == '/parent/attendance') return _attendance(personId, q);
  if (url == '/parent/grades') return _grades(personId, q);
  if (url == '/parent/points/progress') {
    final rows = _pointRows(personId).reversed.toList();
    return {
      'ok': true,
      'meta': {'total_points': rows.fold<num>(0, (s, r) => s + (r['points'] as num))},
      'progress': [for (final r in rows) {'date': r['date'], 'total_points': r['points'], 'point_records': 1}],
    };
  }
  if (url == '/parent/points') {
    final rows = _pointRows(personId);
    return {'ok': true, 'meta': {'total': rows.length, 'total_points': 0}, 'points': rows.take(_limit(q, 20)).toList()};
  }
  if (url == '/parent/ranking') {
    final all = _ranked([
      for (var i = 0; i < _classmates.length; i++) {'person_id': 500 + i, 'full_name': _classmates[i], 'total_points': 31 - i * 6},
      {'person_id': personId, 'full_name': me?['full_name'], 'total_points': 22, 'is_current_student': true},
    ], 'total_points');
    final mine = all.firstWhere((r) => r['is_current_student'] == true);
    return {
      'ok': true,
      'meta': {'total_students': all.length, 'current_student_rank': mine['rank'], 'current_student_points': mine['total_points']},
      'ranking': all,
    };
  }
  if (url == '/parent/exams/ranking') {
    final exam = _examList.firstWhere((e) => '${e['id']}' == '${q['exam_id']}');
    final all = _ranked([
      for (var i = 0; i < _classmates.length; i++) {'exam_result_id': 700 + i, 'full_name': _classmates[i], 'score': 95 - i * 8},
      {'exam_result_id': 799, 'full_name': me?['full_name'], 'score': exam['current_score'], 'is_current_student': true},
    ], 'score');
    return {
      'ok': true,
      'meta': {'total_students': all.length, 'current_student_rank': all.firstWhere((r) => r['is_current_student'] == true)['rank']},
      'ranking': all,
    };
  }
  if (url == '/parent/exams') return {'ok': true, 'result': _examList};
  if (url == '/parent/calendar') {
    final items = [
      {'key': 'event:1', 'source': 'event', 'title': 'Parent meeting', 'status': 'published', 'all_day': false,
        'start_date': _d(2), 'end_date': _d(2), 'start_time': '17:00', 'end_time': '18:00', 'location': 'Room 204'},
      {'key': 'event:2', 'source': 'event', 'title': 'Sports day', 'status': 'published', 'all_day': true,
        'start_date': _d(6), 'end_date': _d(6), 'location': 'Stadium'},
      {'key': 'holiday:1', 'source': 'holiday', 'title': 'Autumn break', 'all_day': true, 'start_date': _d(9), 'end_date': _d(13)},
      {'key': 'exam_period:3', 'source': 'exam_period', 'title': 'Term 2 Finals', 'all_day': true, 'start_date': _d(25), 'end_date': _d(25)},
    ];
    return {
      'ok': true,
      'result': items
          .where((i) => '${i['end_date']}'.compareTo('${q['from']}') >= 0 && '${i['start_date']}'.compareTo('${q['to']}') <= 0)
          .toList(),
    };
  }
  if (url == '/parent/notifications/unread-count') {
    return {'unread_count': personId == 100 ? _notifications.where((n) => n['is_read'] != true).length : 0};
  }
  if (url == '/parent/notifications/read-all') {
    _notifications = [for (final n in _notifications) {...n, 'is_read': true}];
    return {};
  }
  if (url.startsWith('/parent/notifications/') && method == 'patch') {
    final id = int.parse(url.split('/')[3]);
    _notifications = [for (final n in _notifications) n['id'] == id ? {...n, 'is_read': true} : n];
    return {};
  }
  if (url == '/parent/notifications') return {'items': personId == 100 ? _notifications : [], 'total': 3};
  return null;
}
