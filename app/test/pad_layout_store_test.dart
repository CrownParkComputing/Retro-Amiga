import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/amiga_keys.dart';
import 'package:uae4arm2026/data/pad_layout.dart';

void main() {
  test('the file the designer writes is the file the emulator reads', () {
    // The designer (launcher process) and the pad (emulator process) only
    // agree through this file, so what one writes has to parse as what the
    // other expects - including the Java side, which reads it as one line.
    const PadLayout layout = PadLayout(
      stick: Offset2(0.2, 0.7),
      buttons: Offset2(0.8, 0.7),
      style: PadStyle.cd32,
      customButtons: <PadButton>[PadButton.key(AmigaKeys.space)],
    );

    final Directory dir = Directory.systemTemp.createTempSync('padlayout');
    final File file = File('${dir.path}/pad_layout.json');
    file.writeAsStringSync(layout.encode());

    // Java joins the lines it reads, so the encoding must survive that.
    final String asJavaReadsIt = file.readAsLinesSync().join();
    final PadLayout back = PadLayout.decode(asJavaReadsIt);

    expect(back.style, PadStyle.cd32);
    expect(back.stick.dx, closeTo(0.2, 1e-9));
    expect(back.customButtons.single.key?.code, 0x40);
    expect(jsonDecode(asJavaReadsIt), isA<Map<String, Object?>>());

    dir.deleteSync(recursive: true);
  });
}
