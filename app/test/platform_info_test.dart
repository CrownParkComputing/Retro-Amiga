// The Files-app heading onboarding names depends on which device is in the
// user's hand. It said "On My iPad" unconditionally, which only stopped being
// true when TARGETED_DEVICE_FAMILY widened to "1,2".
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/platform_info.dart';

void main() {
  test('phone-sized screens are not tablets', () {
    // Portrait and landscape, because the threshold reads the shortest side
    // and a rotated phone must not become a tablet.
    expect(isTabletSized(const Size(440, 956)), isFalse); // 17 Pro Max
    expect(isTabletSized(const Size(956, 440)), isFalse); // ...rotated
    expect(isTabletSized(const Size(320, 568)), isFalse);
  });

  test('tablet-sized screens are tablets', () {
    expect(isTabletSized(const Size(834, 1210)), isTrue); // iPad 11in
    expect(isTabletSized(const Size(1210, 834)), isTrue); // ...rotated
    expect(isTabletSized(const Size(744, 1133)), isTrue); // iPad mini
  });

  test('600 is the boundary, and is a tablet', () {
    expect(isTabletSized(const Size(599, 900)), isFalse);
    expect(isTabletSized(const Size(600, 900)), isTrue);
  });
}
