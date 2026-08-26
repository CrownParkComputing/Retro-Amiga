import 'dart:io';

import 'package:flutter/material.dart';

/// One page of the getting-started guide.
class GuideStep {
  const GuideStep({
    required this.title,
    required this.icon,
    required this.body,
  });

  final String title;
  final IconData icon;
  final List<Widget> body;
}

/// The paged guide: a title, a body, and Back/Next.
///
/// The chrome used to live inside OnboardingScreen, which meant the only way
/// to read any of this was to be in the middle of first-run setup. It is a
/// widget of its own now so About can offer it too -- the questions it answers
/// ("where do I put my files?") are asked most often by someone who has
/// already finished setup and cannot work out why the app cannot see their
/// collection.
class GettingStartedGuide extends StatefulWidget {
  const GettingStartedGuide({
    super.key,
    required this.steps,
    this.onClose,
    this.onBack,
    this.closeLabel = 'Done',
  });

  final List<GuideStep> steps;

  /// Where the guide goes when it is finished or dismissed, or null when it
  /// IS the screen -- the Help tab has nowhere to close to, and a close
  /// button there is a control that does nothing.
  final VoidCallback? onClose;

  /// Where Back goes from the FIRST page. Without it, backing out of page one
  /// runs onClose -- which in a wizard means the Back button carries you
  /// forwards to the next step, which is worse than doing nothing.
  final VoidCallback? onBack;

  /// What the last page's button says. "Done" from the shelf; setup uses
  /// something that names where it goes back to.
  final String closeLabel;

  @override
  State<GettingStartedGuide> createState() => _GettingStartedGuideState();
}

class _GettingStartedGuideState extends State<GettingStartedGuide> {
  final PageController _controller = PageController();
  int _at = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int to) {
    if (to < 0) {
      final VoidCallback? back = widget.onBack;
      // No way back and nothing behind us: stay put rather than treat Back as
      // a way onwards.
      if (back != null) back();
      return;
    }
    if (to >= widget.steps.length) {
      final VoidCallback? close = widget.onClose;
      // Nowhere to go: wrap back to the start so the guide is ready for the
      // next reader rather than stuck on its last page.
      if (close == null) return _controller.jumpToPage(0);
      return close();
    }
    _controller.animateToPage(
      to,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    final int at = _at.clamp(0, widget.steps.length - 1);
    final GuideStep step = widget.steps[at];
    final bool last = at == widget.steps.length - 1;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
          child: Row(
            children: <Widget>[
              if (widget.onClose != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close the guide',
                  onPressed: widget.onClose,
                )
              else
                const SizedBox(width: 12),
              Icon(step.icon, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  step.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${at + 1} of ${widget.steps.length}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // A bar rather than a row of dots: with eight or nine steps the dots
        // stop being countable, and "how much is left" is the only thing
        // anyone reads them for.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (at + 1) / widget.steps.length,
              minHeight: 4,
            ),
          ),
        ),
        Expanded(
          // Swipeable as well as buttoned: on a phone this is the gesture
          // people try first, and a guide that refuses it feels stuck.
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.steps.length,
            onPageChanged: (int i) => setState(() => _at = i),
            itemBuilder: (BuildContext context, int i) => ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              children: widget.steps[i].body,
            ),
          ),
        ),
        const Divider(height: 20),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Row(
            children: <Widget>[
              OutlinedButton(
                // Greyed rather than hidden on the first page when there is
                // nowhere behind: a button that vanishes shifts everything
                // beside it.
                onPressed: (at == 0 && widget.onBack == null)
                    ? null
                    : () => _go(at - 1),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _go(at + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(last ? widget.closeLabel : 'Next'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The parts of the guide that are the same for everyone, written for someone
/// who has never run an emulator.
///
/// The assumption behind every line here is that the reader does not already
/// know what a Kickstart is, does not know that .adf is a floppy, and has no
/// idea why an app cannot simply open their Downloads folder. Every one of
/// those has arrived as a review rather than as a question, which is the
/// problem: a confused user does not write in, they rate the app and leave.
class GettingStartedSteps {
  const GettingStartedSteps._();

  static Widget _p(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: const TextStyle(height: 1.45)),
  );

  static Widget _point(IconData icon, String title, String body) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(body),
      isThreeLine: body.length > 60,
    ),
  );

  /// "What is this thing and what do I need?"
  /// [hasRealKickstart] null where it is not known -- the Help tab is read
  /// long after setup, and claiming either way there would be a guess
  /// presented as a fact.
  static GuideStep whatYouNeed({bool? hasRealKickstart}) => GuideStep(
    title: 'What an Amiga needs',
    icon: Icons.help_outline,
    body: <Widget>[
      _p(
        'This app is an Amiga — a computer from 1985 — running inside your '
        'phone or tablet. Like the real machine, it needs two things: the '
        'chip that makes it an Amiga, and something to run.',
      ),
      _point(
        Icons.memory,
        'A Kickstart ROM',
        hasRealKickstart == true
            ? 'You already have one, and it will be used. Nothing to do.'
            : 'The machine\'s built-in software. One is already included — '
                  'AROS, a free replacement — so the Amiga boots right now. A '
                  'real Kickstart (Amiga Forever is the usual legitimate '
                  'source) runs more games; drop it in with everything else '
                  'and it is picked up automatically.',
      ),
      if (Platform.isIOS)
        _point(
          Icons.speed,
          'One thing iOS cannot do',
          'Apple does not allow an app to generate code while it runs, so no '
              'emulator on the App Store has a JIT. Everything here is set up '
              'to run as well as it can without one — most games are '
              'unaffected; the heaviest 68040 setups are the ones that '
              'notice.',
        ),
      _point(
        Icons.videogame_asset_outlined,
        'Games and programs',
        'Usually .adf (a floppy disk), .lha (a WHDLoad game), or .hdf (a hard '
            'disk). Often inside a .zip, which is fine — zips are opened for '
            'you.',
      ),
      _p(
        'You do not need anything else, and you do not have to get this right '
        'now. You can finish setup with no files at all and still watch an '
        'Amiga boot.',
      ),
    ],
  );

  /// The platform's own answer to "where do I put my files?".
  ///
  /// This is the step the app most needed and did not have. iOS and Android
  /// restrict file access in completely different ways, both of them
  /// surprising if you have not met them, and neither of them the app's
  /// choice.
  static GuideStep whereFilesGo() {
    if (Platform.isIOS) {
      return GuideStep(
        title: 'Where to put your files',
        icon: Icons.folder_special_outlined,
        body: <Widget>[
          _p(
            'On iPhone and iPad an app may only see its own folder. That is '
            'Apple\'s rule for every app, not something this one chose, and '
            'it is why the app cannot simply open your Downloads.',
          ),
          _p('The folder is there for you to use. To reach it:'),
          _point(
            Icons.looks_one_outlined,
            'Open the Files app',
            'It is on your home screen — the blue folder.',
          ),
          _point(
            Icons.looks_two_outlined,
            'Tap "On My iPhone" or "On My iPad"',
            'Then open the folder named Retro-Amiga. If you do not see it, '
                'come back here and finish setup once — the app creates it on '
                'first run.',
          ),
          _point(
            Icons.looks_3_outlined,
            'Put your files in it',
            'Copy or move .zip, .adf, .lha, .hdf or Kickstart files in. '
                'Long-press a file anywhere in Files, choose Copy, then paste '
                'it here.',
          ),
          _point(
            Icons.ios_share,
            'Or send them straight in',
            'From Safari, Mail or AirDrop, use Share → Save to Files, and '
                'pick the Retro-Amiga folder as the destination.',
          ),
          _p(
            'Then come back and tap Rescan. Zips are unpacked and everything '
            'is sorted into Floppies, HardDrives, CDROMs and Kickstarts for '
            'you.',
          ),
          _point(
            Icons.cloud_off,
            'iCloud and other apps',
            'The app cannot read files that live only in iCloud Drive or '
                'inside another app. Copy them into the Retro-Amiga folder '
                'first and they will work.',
          ),
        ],
      );
    }

    if (Platform.isAndroid) {
      return GuideStep(
        title: 'Where to put your files',
        icon: Icons.folder_special_outlined,
        body: <Widget>[
          _p(
            'On Android you keep your collection wherever you like and simply '
            'show the app where it is. Nothing is copied and nothing is '
            'moved — the app reads your files where they already are.',
          ),
          _point(
            Icons.looks_one_outlined,
            'Tap "Choose folder"',
            'Android opens its own file picker. This app never sees your '
                'storage until you point at a folder here.',
          ),
          _point(
            Icons.looks_two_outlined,
            'Open the folder your Amiga files are in',
            'Pick the folder itself — the one with your .adf, .lha or .zip '
                'files in it, or the folder above them. Everything inside it '
                'is included.',
          ),
          _point(
            Icons.looks_3_outlined,
            'Tap "Use this folder", then Allow',
            'That grant is what gives the app access. It lasts: it survives '
                'closing the app, updating it and restarting the device.',
          ),
          const SizedBox(height: 4),
          const Text(
            'SD cards and USB drives',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _p(
            'These work exactly the same way — the picker can reach them, it '
            'just does not always show them straight away.',
          ),
          _point(
            Icons.sd_card_outlined,
            'Finding a card or drive in the picker',
            'Tap the ☰ menu at the top left. Your SD card or USB drive is '
                'listed by name, below Internal storage. Choose it, then '
                'carry on into your folder as normal.',
          ),
          _point(
            Icons.usb,
            'If it is not listed',
            'Plug the drive in before opening the picker, and give the system '
                'a moment to mount it. On some devices you also have to tap '
                'the ⋮ menu and turn on "Show internal storage" to see '
                'everything.',
          ),
          _point(
            Icons.swap_horiz,
            'If you move or swap the card',
            'The grant belongs to that particular folder on that particular '
                'card. Swap the card and the app will ask again — come back '
                'to Files and choose the folder once more.',
          ),
        ],
      );
    }

    return GuideStep(
      title: 'Where to put your files',
      icon: Icons.folder_special_outlined,
      body: <Widget>[
        _p(
          'Choose any folder you can read. Your collection stays where it is '
          'and is read in place — nothing is copied and nothing is moved.',
        ),
        _point(
          Icons.folder_open,
          'Adding more later',
          'Drop new files into the same folder and press Rescan on the Files '
              'page. There is no import step to remember.',
        ),
      ],
    );
  }

  /// "I have finished setup — now what?"
  static GuideStep firstGame() => const GuideStep(
    title: 'Playing your first game',
    icon: Icons.play_circle_outline,
    body: <Widget>[
      _Step(
        n: '1',
        title: 'Open Games and make a setup',
        body: 'A setup is a machine plus a disk: which Amiga to be, and what '
            'to put in it. The wizard asks one question at a time and picks '
            'sensible answers for the rest.',
      ),
      _Step(
        n: '2',
        title: 'Press play',
        body: 'The Amiga starts in the panel, with the app still around it. '
            'It is not a separate screen — the buttons along the bottom stay '
            'with you.',
      ),
      _Step(
        n: '3',
        title: 'The controls appear over the picture',
        body: 'A stick and buttons, unless you have a real controller '
            'connected — then they stay out of the way. The layout button on '
            'the bottom strip moves and resizes them however you like.',
      ),
      _Step(
        n: '4',
        title: 'If a game ignores the stick',
        body: 'Amiga games read one of two joystick sockets and there is no '
            'way to tell which from the outside. Tap the plug button on the '
            'bottom strip to move your controls to the other port. That is '
            'the fix for most "the buttons do nothing" moments.',
      ),
      _Step(
        n: '5',
        title: 'Stopping keeps your place',
        body: 'Pause writes a snapshot and puts it on the Resume shelf, so '
            'you come back to the exact moment you left.',
      ),
    ],
  );
}

/// A numbered instruction, so the ordered steps read as an order.
class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.body});

  final String n;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 13,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              n,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
