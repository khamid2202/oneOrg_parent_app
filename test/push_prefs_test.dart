import 'package:flutter_test/flutter_test.dart';
import 'package:oneorg_parents/api/api_client.dart';
import 'package:oneorg_parents/api/parent_api.dart';
import 'package:oneorg_parents/api/storage.dart';
import 'package:oneorg_parents/state/push.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(Push, Storage)> make(Map<String, Object> saved) async {
    SharedPreferences.setMockInitialValues(saved);
    final storage = await Storage.open();
    return (Push(ParentApi(ApiClient(storage)), storage), storage);
  }

  test('everything is on by default', () async {
    final (push, _) = await make({});
    expect(Push.kinds.every(push.isOn), isTrue);
  });

  test('switches are saved on the device, unknown kinds are dropped', () async {
    final (push, storage) = await make({'push_muted': 'grade,old_kind'});
    expect(push.muted, {'grade'});

    await push.setOn('attendance_present', false);
    await push.setOn('grade', true);
    expect(storage.getString(Storage.pushMuted), 'attendance_present');
    expect(push.isOn('grade'), isTrue);

    await push.setOn('attendance_present', true);
    expect(storage.getString(Storage.pushMuted), isNull);
  });
}
