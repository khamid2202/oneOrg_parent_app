import 'package:flutter/foundation.dart';

import '../api/parent_api.dart';
import '../api/storage.dart';

class Child {
  Child({
    required this.id,
    required this.code,
    required this.fullName,
    required this.shortName,
    required this.picture,
    required this.className,
    required this.teacherName,
    required this.enrolled,
  });

  final int id;
  final String code;
  final String fullName;
  final String shortName;
  final String? picture;
  final String className;
  final String teacherName;
  final bool enrolled;

  /// The class the child is in now; else the most recent one.
  static Map<String, dynamic>? _currentGroup(List<dynamic> groups) {
    final real = groups.cast<Map<String, dynamic>>().where((g) => g['id'] != null).toList();
    return real.where((g) => g['leave_date'] == null && g['status'] == 'studying').firstOrNull ??
        real.where((g) => g['leave_date'] == null).firstOrNull ??
        real.lastOrNull;
  }

  factory Child.fromJson(Map<String, dynamic> json) {
    final group = _currentGroup(json['groups'] as List<dynamic>? ?? const []);
    final parts = '${json['full_name'] ?? ''}'.trim().split(RegExp(r'\s+'));
    return Child(
      id: (json['id'] as num).toInt(),
      code: '${json['la_id'] ?? ''}',
      fullName: '${json['full_name'] ?? ''}',
      // "Valiyev Ali Olimovich": the given name is second.
      shortName: parts.length > 1 ? parts[1] : parts.first,
      picture: json['picture'] as String?,
      className: '${group?['class_pair_compact'] ?? ''}',
      teacherName: '${group?['teacher_name'] ?? ''}',
      enrolled: group != null && group['leave_date'] == null,
    );
  }
}

/// The parent's children and which one is open.
class Children extends ChangeNotifier {
  Children(this._api, this._storage);

  final ParentApi _api;
  final Storage _storage;

  List<Child> list = const [];
  bool loading = false;
  Object? error;
  int? _selectedId;

  Child? get child =>
      list.where((c) => c.id == _selectedId).firstOrNull ?? list.firstOrNull;

  Future<void> load() async {
    loading = list.isEmpty;
    error = null;
    notifyListeners();
    try {
      final body = await _api.children();
      final persons = ((body['result'] as Map?)?['persons'] as List?) ?? const [];
      final all = persons.map((p) => Child.fromJson(p as Map<String, dynamic>)).toList();
      // Children in a class now come first, so the default one has a schedule.
      list = [...all.where((c) => c.enrolled), ...all.where((c) => !c.enrolled)];
      _selectedId ??= int.tryParse(_storage.getString(Storage.child) ?? '');
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void select(int id) {
    _selectedId = id;
    _storage.setString(Storage.child, '$id');
    notifyListeners();
  }

  void reset() {
    list = const [];
    _selectedId = null;
    error = null;
  }
}
