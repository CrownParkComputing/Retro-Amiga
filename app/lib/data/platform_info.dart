import 'package:flutter/widgets.dart';
import 'dart:io';

/// What Apple calls this device inside the Files app.
///
/// The app's folder lives under "On My iPhone" on a phone and "On My iPad" on
/// a tablet, and instructions that name the wrong one send the user looking
/// for a heading that is not on their screen. Onboarding used to say iPad
/// unconditionally, which was true only while the app was iPad-only --
/// widening TARGETED_DEVICE_FAMILY to "1,2" made it wrong on every iPhone.
///
/// iPadOS reports itself as iOS and dart:io cannot tell the two apart, so the
/// idiom comes from the shortest side. 600dp is the conventional tablet
/// threshold and every iPhone, the Pro Max included, is comfortably under it.
String filesAppDeviceName(BuildContext context) {
  if (!Platform.isIOS) return 'this device';
  return isTabletSized(MediaQuery.of(context).size)
      ? 'On My iPad'
      : 'On My iPhone';
}

/// Split out from [filesAppDeviceName] so the threshold itself is testable:
/// `Platform.isIOS` is false under `flutter test`, which would otherwise make
/// the phone/tablet branch unreachable from a test.
bool isTabletSized(Size size) => size.shortestSide >= 600;
