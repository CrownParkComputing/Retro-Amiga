/// Which shelf a pick sits on.
enum MusicShelf {
  demo('Demo tunes', 'The scene\'s ten'),
  game('Game soundtracks', 'Ten that sold the machine');

  const MusicShelf(this.title, this.blurb);

  final String title;
  final String blurb;
}

/// One tune worth having.
class MusicPick {
  const MusicPick({
    required this.title,
    required this.credit,
    required this.shelf,
    required this.keywords,
  });

  /// What the tune is called.
  final String title;

  /// Composer where it is known, otherwise the group or game it came from.
  final String credit;

  final MusicShelf shelf;

  /// Lower-case fragments that identify the file. A module travels under
  /// several names - mod.space_debris, space debris.mod, spacedeb.mod - so
  /// matching is on fragments of the squashed name rather than an exact
  /// filename.
  final List<String> keywords;

  /// True if [fileName] looks like this tune.
  ///
  /// The name is squashed to letters and digits first, so underscores,
  /// spaces, hyphens and the mod. prefix all stop mattering.
  bool matches(String fileName) {
    final String squashed = squash(fileName);
    return keywords.any(squashed.contains);
  }

  static String squash(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Twenty tunes: ten from the demoscene, ten from games.
///
/// Nothing ships with the app. These are modules other people wrote, and the
/// good archives - Aminet, The Mod Archive, Modland - are a download away.
/// What this list does is tell you which ones to go and get, and light up when
/// you have them, which is the same job the C64 side does for SIDs.
///
/// Credits name the composer only where that is settled. Where a tune is
/// better known by its demo or its game than by whoever wrote it, that is what
/// is given - a confident wrong attribution would be worse than an honest
/// vague one.
class MusicPicks {
  const MusicPicks._();

  static const List<MusicPick> all = <MusicPick>[
    // ---- the scene ----
    MusicPick(
      title: 'Space Debris',
      credit: 'Captain / Markus Kaarlonen',
      shelf: MusicShelf.demo,
      keywords: <String>['spacedebris', 'spacedeb'],
    ),
    MusicPick(
      title: 'Enigma',
      credit: 'Jesper Kyd, for Phenomena',
      shelf: MusicShelf.demo,
      keywords: <String>['enigma'],
    ),
    MusicPick(
      title: 'Elysium',
      credit: 'Jester / Volker Tripp',
      shelf: MusicShelf.demo,
      keywords: <String>['elysium'],
    ),
    MusicPick(
      title: 'Global Trash',
      credit: 'Romeo Knight',
      shelf: MusicShelf.demo,
      keywords: <String>['globaltrash', 'globtrash'],
    ),
    MusicPick(
      title: 'Cream of the Earth',
      credit: 'Romeo Knight',
      shelf: MusicShelf.demo,
      keywords: <String>['creamoftheearth', 'cream'],
    ),
    MusicPick(
      title: 'State of the Art',
      credit: 'Travolta, for Spaceballs',
      shelf: MusicShelf.demo,
      keywords: <String>['stateoftheart', 'stateofart', 'sota'],
    ),
    MusicPick(
      title: '9 Fingers',
      credit: 'Travolta, for Spaceballs',
      shelf: MusicShelf.demo,
      keywords: <String>['9fingers', 'ninefingers'],
    ),
    MusicPick(
      title: 'Desert Dream',
      credit: 'Kefrens',
      shelf: MusicShelf.demo,
      keywords: <String>['desertdream', 'desert'],
    ),
    MusicPick(
      title: 'Mental Hangover',
      credit: 'Scoopex',
      shelf: MusicShelf.demo,
      keywords: <String>['mentalhangover', 'hangover'],
    ),
    MusicPick(
      title: 'Klisje Paa Klisje',
      credit: 'Dizzy',
      shelf: MusicShelf.demo,
      keywords: <String>['klisje', 'klisjepaaklisje'],
    ),

    // ---- games ----
    MusicPick(
      title: 'Turrican II',
      credit: 'Chris Huelsbeck',
      shelf: MusicShelf.game,
      keywords: <String>['turrican'],
    ),
    MusicPick(
      title: 'Shadow of the Beast',
      credit: 'David Whittaker',
      shelf: MusicShelf.game,
      keywords: <String>['shadowofthebeast', 'beast'],
    ),
    MusicPick(
      title: 'Lotus Turbo Challenge 2',
      credit: 'Barry Leitch',
      shelf: MusicShelf.game,
      keywords: <String>['lotus'],
    ),
    MusicPick(
      title: 'Xenon 2: Megablast',
      credit: 'Bomb the Bass, converted by David Whittaker',
      shelf: MusicShelf.game,
      keywords: <String>['megablast', 'xenon'],
    ),
    MusicPick(
      title: 'Apidya',
      credit: 'Chris Huelsbeck',
      shelf: MusicShelf.game,
      keywords: <String>['apidya'],
    ),
    MusicPick(
      title: 'Agony',
      credit: 'Tim Wright / CoLD SToRAGE',
      shelf: MusicShelf.game,
      keywords: <String>['agony'],
    ),
    MusicPick(
      title: 'Alien Breed',
      credit: 'Allister Brimble',
      shelf: MusicShelf.game,
      keywords: <String>['alienbreed'],
    ),
    MusicPick(
      title: 'Project-X',
      credit: 'Allister Brimble',
      shelf: MusicShelf.game,
      keywords: <String>['projectx'],
    ),
    MusicPick(
      title: 'Superfrog',
      credit: 'Allister Brimble',
      shelf: MusicShelf.game,
      keywords: <String>['superfrog'],
    ),
    MusicPick(
      title: 'Cannon Fodder',
      credit: 'Richard Joseph and Jon Hare',
      shelf: MusicShelf.game,
      keywords: <String>['cannonfodder', 'warhasnever'],
    ),
  ];

  static List<MusicPick> of(MusicShelf shelf) =>
      all.where((MusicPick p) => p.shelf == shelf).toList();
}
