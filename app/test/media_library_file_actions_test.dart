import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/file_category.dart';
import 'package:uae4arm2026/data/media_library.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('media-actions');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('rename stays in the media directory and preserves metadata', () async {
    final File source = File('${directory.path}/mod.old.mod')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final MediaFile file = MediaFile(
      path: source.path,
      category: FileCategory.music,
      size: source.lengthSync(),
    );

    final MediaFile renamed = await MediaLibrary.rename(file, 'mod.new.mod');

    expect(File(renamed.path).existsSync(), isTrue);
    expect(renamed.directory, directory.path);
    expect(renamed.category, FileCategory.music);
    expect(renamed.size, 3);
    expect(source.existsSync(), isFalse);
  });

  test('rename rejects folders and existing names', () async {
    final File source = File('${directory.path}/one.mod')
      ..writeAsStringSync('1');
    File('${directory.path}/two.mod').writeAsStringSync('2');
    final MediaFile file = MediaFile(
      path: source.path,
      category: FileCategory.music,
      size: 1,
    );

    await expectLater(
      MediaLibrary.rename(file, '../outside.mod'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      MediaLibrary.rename(file, 'two.mod'),
      throwsA(isA<FileSystemException>()),
    );
    expect(source.existsSync(), isTrue);
  });

  test('delete removes the selected local file', () async {
    final File source = File('${directory.path}/remove.mod')
      ..writeAsStringSync('module');
    final MediaFile file = MediaFile(
      path: source.path,
      category: FileCategory.music,
      size: source.lengthSync(),
    );

    await MediaLibrary.delete(file);

    expect(source.existsSync(), isFalse);
  });
}
