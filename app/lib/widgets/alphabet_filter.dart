import 'package:flutter/material.dart';

/// A strip of initials across the top of a long list.
///
/// A hundred disks is more than anyone scrolls through, and search only helps
/// when you already know the name. Picking a letter is how you browse a shelf:
/// you go to roughly where the game is and read what is there.
///
/// Only the letters actually present are offered, so a tap always lands on
/// something. Tapping the chosen one again clears it.
class AlphabetFilter extends StatelessWidget {
  const AlphabetFilter({
    super.key,
    required this.initials,
    required this.selected,
    required this.onSelected,
  });

  /// The initials present in the list, in the order they should appear.
  final List<String> initials;

  /// The chosen initial, or null for everything.
  final String? selected;

  final ValueChanged<String?> onSelected;

  /// The bucket a name belongs in: its first letter, or '#' for anything that
  /// does not start with one - a title beginning with a digit or a bracket is
  /// still on the shelf, and dropping it would make the filter lie.
  static String initialOf(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return '#';
    final String first = trimmed[0].toUpperCase();
    return RegExp('[A-Z]').hasMatch(first) ? first : '#';
  }

  /// The initials present in [names], '#' first and then A to Z.
  static List<String> from(Iterable<String> names) {
    final Set<String> found = names.map(initialOf).toSet();
    final List<String> letters = found.where((String i) => i != '#').toList()
      ..sort();
    return <String>[if (found.contains('#')) '#', ...letters];
  }

  @override
  Widget build(BuildContext context) {
    // Always drawn, even for one letter: a strip that comes and goes with the
    // list's length moves the rows under your thumb, and the C64 front end
    // keeps it fixed for the same reason.

    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          _Chip(
            label: 'All',
            active: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final String initial in initials)
            _Chip(
              label: initial,
              active: initial == selected,
              onTap: () => onSelected(initial == selected ? null : initial),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: active
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 26),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
