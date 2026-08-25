import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/media_folder.dart';

/// The tree URI a folder grant comes back as tells the user nothing:
/// content://com.android.externalstorage.documents/tree/primary%3AAmiga. It is
/// unpacked so they can see which folder they actually picked - the only way
/// to notice they picked the wrong one.
void main() {
  String path(String uri) => MediaFolder.pathFromTreeUri(uri);

  test('internal storage becomes an /sdcard path', () {
    expect(
      path(
        'content://com.android.externalstorage.documents/tree/primary%3AAmiga',
      ),
      '/sdcard/Amiga',
    );
  });

  test('nested folders keep their separators', () {
    expect(
      path(
        'content://com.android.externalstorage.documents/tree/'
        'primary%3AUAE4Arm%2Ffloppies',
      ),
      '/sdcard/UAE4Arm/floppies',
    );
  });

  test('the root of internal storage is /sdcard, not /sdcard/', () {
    expect(
      path('content://com.android.externalstorage.documents/tree/primary%3A'),
      '/sdcard',
    );
  });

  test(
    'an SD card keeps its volume id rather than pretending to be /sdcard',
    () {
      expect(
        path(
          'content://com.android.externalstorage.documents/tree/'
          '1A2B-3C4D%3AAmiga',
        ),
        '/storage/1A2B-3C4D/Amiga',
      );
    },
  );

  test('spaces and brackets in a folder name survive decoding', () {
    expect(
      path(
        'content://com.android.externalstorage.documents/tree/'
        'primary%3AAmiga%20Games%20%5Bold%5D',
      ),
      '/sdcard/Amiga Games [old]',
    );
  });

  // A URI that is not a tree, or is not shaped as expected, is shown as-is
  // rather than guessed at.
  test('an unrecognised uri is returned unchanged', () {
    expect(path('content://something/else'), 'content://something/else');
  });

  test('a document id with no volume is returned as the id', () {
    expect(
      path('content://com.android.externalstorage.documents/tree/plainfolder'),
      'plainfolder',
    );
  });
}
