import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/widgets/alphabet_filter.dart';

void main() {
  group('AlphabetFilter', () {
    test('buckets a name by its first letter', () {
      expect(AlphabetFilter.initialOf('IKPlus.adf'), 'I');
      expect(AlphabetFilter.initialOf('gods.adf'), 'G');
      // Anything not starting with a letter still has to land somewhere, or
      // the strip would hide files that exist.
      expect(AlphabetFilter.initialOf('1942.adf'), '#');
      expect(AlphabetFilter.initialOf('[cr] Rastan.adf'), '#');
      expect(AlphabetFilter.initialOf('  '), '#');
      expect(AlphabetFilter.initialOf(''), '#');
    });

    test('offers only the initials present, digits first', () {
      final List<String> initials = AlphabetFilter.from(<String>[
        'Gods.adf',
        'apidya.adf',
        '1942.adf',
        'Gods disk 2.adf',
      ]);
      expect(initials, <String>['#', 'A', 'G']);
      // No file, no letter: every chip has to lead somewhere.
      expect(initials.contains('B'), isFalse);
    });
  });
}
