import 'package:flutter_test/flutter_test.dart';
import 'package:oneorg_parents/screens/auth_screens.dart';

String fmt(String input) => UzPhoneFormatter()
    .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: input))
    .text;

void main() {
  test('groups nine digits as 90 123 45 67', () {
    expect(fmt('901234567'), '90 123 45 67');
    expect(fmt('9012'), '90 12');
  });
  test('drops a pasted country code and stray characters', () {
    expect(fmt('+998 (90) 123-45-67'), '90 123 45 67');
  });
  test('stops at nine digits', () {
    expect(fmt('9012345678'), '90 123 45 67');
  });
}
