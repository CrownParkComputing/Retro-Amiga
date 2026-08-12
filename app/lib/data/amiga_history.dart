/// One entry in the history screen: a heading and a paragraph.
class HistoryEntry {
  const HistoryEntry(this.title, this.detail, {this.aside});

  final String title;
  final String detail;

  /// A short right-hand note - a year, a chip name, a composer's tool.
  final String? aside;
}

/// What the Amiga was, told in five tabs.
///
/// Static const data. It is here rather than fetched because it does not
/// change, and because a handheld on a train should still have it.
class AmigaHistory {
  const AmigaHistory._();

  static const List<HistoryEntry> machines = <HistoryEntry>[
    HistoryEntry(
      'Amiga 1000',
      'The original, and the one the engineers signed - their names, and Jay '
          'Miner\'s dog Mitchy\'s paw print, are moulded inside the case. '
          '7.16MHz 68000, 256K, and the OCS chipset that did the work no other '
          'home computer could.',
      aside: '1985',
    ),
    HistoryEntry(
      'Amiga 500',
      'The one almost everyone actually had. Same chipset in a keyboard case '
          'at a price a family would pay, which is why the software library is '
          'what it is. 512K, expandable to 1MB with the trapdoor RAM everyone '
          'fitted.',
      aside: '1987',
    ),
    HistoryEntry(
      'Amiga 2000 and 3000',
      'The expandable machines: Zorro slots, accelerators, Video Toaster. The '
          '3000 brought the 68030 and ECS, and put the Amiga into television '
          'studios for a decade.',
      aside: '1987-1990',
    ),
    HistoryEntry(
      'Amiga 600',
      'An A500 shrunk, with IDE and PCMCIA but no numeric keypad and no '
          'expansion bus. Unloved at launch, and now the favourite of anyone '
          'fitting a solid-state drive to a machine from 1992.',
      aside: '1992',
    ),
    HistoryEntry(
      'Amiga 1200',
      'AGA: 256 colours from a palette of 16.8 million, and a 68EC020. The '
          'last Amiga that sold in numbers, and the machine most WHDLoad '
          'installs assume.',
      aside: '1992',
    ),
    HistoryEntry(
      'Amiga 4000 and CD32',
      'The 4000 was the AGA workstation. The CD32 was the world\'s first '
          '32-bit CD console - an A1200 with a CD drive and a seven-button pad '
          '- and it sold well until Commodore ran out of money mid-production.',
      aside: '1992-1993',
    ),
  ];

  static const List<HistoryEntry> story = <HistoryEntry>[
    HistoryEntry(
      'It started as a games console',
      'Jay Miner\'s team at Amiga Corporation were building a 68000-based '
          'console codenamed Lorraine. The video-game crash of 1983 killed the '
          'market before the hardware was finished, so it grew a keyboard and '
          'became a computer.',
      aside: '1982',
    ),
    HistoryEntry(
      'Atari nearly owned it',
      'Amiga Corp took a loan from Atari against the chipset. Commodore paid '
          'the loan back and bought the company outright, days before the '
          'deadline. Atari sued. The Amiga and the Atari ST spent the rest of '
          'the decade as rivals for that reason.',
      aside: '1984',
    ),
    HistoryEntry(
      'The chipset was the point',
      'Agnus, Denise and Paula did the work the CPU did on other machines. '
          'Hardware blitter, hardware sprites, a copper that changed video '
          'registers mid-scanline, and four channels of DMA-driven sampled '
          'sound. A 7MHz machine outran much faster ones because the 68000 was '
          'barely involved.',
    ),
    HistoryEntry(
      'The demoscene',
      'The copper and the blitter rewarded people who read the hardware '
          'manual properly, so they did. Copper bars, sine scrollers, bob '
          'engines and 50fps parallax became a competitive artform, and the '
          'boing ball demo sold the machine before there was anything to sell.',
    ),
    HistoryEntry(
      'Commodore folded',
      'Bankruptcy in 1994, after years of famously poor marketing of famously '
          'good hardware. The technology went through Escom, Gateway and '
          'others. AmigaOS development never entirely stopped, and neither did '
          'the software.',
      aside: '1994',
    ),
  ];

  static const List<HistoryEntry> greats = <HistoryEntry>[
    HistoryEntry('Shadow of the Beast', 'Thirteen layers of parallax and a Roberts soundtrack. Psygnosis, 1989.'),
    HistoryEntry('Lemmings', 'DMA Design, 1991. A hundred lemmings, one mouse, and the best puzzle design of the decade.'),
    HistoryEntry('Another World', 'Eric Chahi\'s rotoscoped polygons, 1991. Almost no HUD, almost no text.'),
    HistoryEntry('Sensible Soccer', 'Sensible Software, 1992. Tiny players, huge pitch, still the fastest football game made.'),
    HistoryEntry('Speedball 2', 'The Bitmap Brothers, 1990. "ICE CREAM! ICE CREAM!"'),
    HistoryEntry('Turrican II', 'Factor 5, 1991. Enormous levels and Chris Huelsbeck\'s finest hour.'),
    HistoryEntry('Cannon Fodder', 'Sensible Software, 1993. "War has never been so much fun", and it meant it.'),
    HistoryEntry('Monkey Island 2', 'LucasArts, 1991. The Amiga version has the MOD score.'),
    HistoryEntry('Xenon 2: Megablast', 'The Bitmap Brothers, 1989, with Bomb the Bass on the soundtrack.'),
    HistoryEntry('Lotus Turbo Challenge 2', 'Magnetic Fields, 1991. Split-screen at fifty frames a second.'),
    HistoryEntry('Alien Breed', 'Team17, 1991. Aliens, top-down, two-player.'),
    HistoryEntry('Worms', 'Team17, 1995, and it started here.'),
    HistoryEntry('Frontier: Elite II', 'David Braben, 1993. A galaxy on two floppies.'),
    HistoryEntry('Chaos Engine', 'The Bitmap Brothers, 1993. Steampunk before the word.'),
    HistoryEntry('Pinball Dreams', 'Digital Illusions, 1992. Sixty frames, hardware scrolling, perfect physics.'),
    HistoryEntry('Superfrog', 'Team17, 1993, and the intro is still worth watching.'),
    HistoryEntry('Flashback', 'Delphine, 1993. Another World\'s successor, with more game in it.'),
    HistoryEntry('Ruff\'n\'Tumble', 'Renegade, 1994. The best pure platformer on the machine, and late.'),
    HistoryEntry('Stunt Car Racer', 'Geoff Crammond, 1989. Filled polygons and a rollercoaster.'),
    HistoryEntry('Defender of the Crown', 'Cinemaware, 1986. The game that showed people what the machine could draw.'),
  ];

  static const List<HistoryEntry> composers = <HistoryEntry>[
    HistoryEntry(
      'Chris Huelsbeck',
      'Turrican, Apidya, R-Type. Wrote TFMX, his own replayer, because '
          'ProTracker could not do what he wanted.',
    ),
    HistoryEntry(
      'David Whittaker',
      'Over a hundred scores, and a sound driver so distinctive you can name '
          'it from four bars.',
    ),
    HistoryEntry(
      'Allister Brimble',
      'Alien Breed, Superfrog, Project-X. Still working, still on Amiga '
          'projects.',
    ),
    HistoryEntry(
      'Tim Wright (CoLD SToRAGE)',
      'Shadow of the Beast II, Agony, Lemmings. Later wrote for Wipeout.',
    ),
    HistoryEntry(
      'Jesper Kyd',
      'The Silents demos, then Subwar 2050 - and from there to Hitman and '
          'Assassin\'s Creed.',
    ),
    HistoryEntry(
      'Karsten Obarski',
      'Wrote the Ultimate Soundtracker in 1987. Every MOD file, every tracker '
          'since, and the four-channel format this app plays, descend from it.',
    ),
  ];

  static const List<HistoryEntry> notable = <HistoryEntry>[
    HistoryEntry(
      'The MOD file',
      'Samples plus a pattern sequence, all in one file that plays the same '
          'anywhere. Invented on this machine, and the direct ancestor of '
          'every tracker format since.',
    ),
    HistoryEntry(
      'Kickstart and Workbench',
      'Kickstart is the ROM: the operating system\'s kernel and the boot '
          'screen asking for a disk. Workbench is the desktop that loads from '
          'floppy afterwards. You need the right Kickstart for the software, '
          'which is why setup asks for one.',
    ),
    HistoryEntry(
      'Preemptive multitasking, in 1985',
      'Exec scheduled tasks properly while the Mac and PC were still '
          'cooperative at best. On 256K of RAM.',
    ),
    HistoryEntry(
      'WHDLoad',
      'A loader that installs a floppy game to hard disk and patches it to '
          'behave: quit key, save states, working on machines the original '
          'never met. Which is why the .lha files in the library are worth '
          'having.',
    ),
    HistoryEntry(
      'The Video Toaster',
      'A 2000 with a Toaster card did broadcast video effects for a fraction '
          'of studio prices. Babylon 5 and SeaQuest were rendered on Amigas.',
    ),
    HistoryEntry(
      'The guru meditation',
      'The crash screen. A red-bordered box, an error code, and a name taken '
          'from a joystick-balancing meditation toy the engineers kept in the '
          'office.',
    ),
  ];
}
