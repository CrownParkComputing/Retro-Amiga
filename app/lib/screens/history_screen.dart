import 'package:flutter/material.dart';

import '../data/amiga_history.dart';
import '../theme/amiga_theme.dart';

/// The Amiga, in five tabs.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static const List<(String, List<HistoryEntry>)> _tabs =
      <(String, List<HistoryEntry>)>[
        ('The machines', AmigaHistory.machines),
        ('How it happened', AmigaHistory.story),
        ('Twenty greats', AmigaHistory.greats),
        ('Composers', AmigaHistory.composers),
        ('Worth knowing', AmigaHistory.notable),
      ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Column(
        children: <Widget>[
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AmigaColors.text,
            unselectedLabelColor: AmigaColors.textDim,
            indicatorColor: AmigaColors.accent,
            tabs: <Widget>[
              Tab(text: 'The machines'),
              Tab(text: 'How it happened'),
              Tab(text: 'Twenty greats'),
              Tab(text: 'Composers'),
              Tab(text: 'Worth knowing'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                for (final (String, List<HistoryEntry>) tab in _tabs)
                  _EntryList(entries: tab.$2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  const _EntryList({required this.entries});

  final List<HistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: entries.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int i) {
        final HistoryEntry entry = entries[i];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AmigaColors.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AmigaColors.text,
                      ),
                    ),
                  ),
                  if (entry.aside != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AmigaColors.workbenchBlue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        entry.aside!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                entry.detail,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AmigaColors.textDim,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
