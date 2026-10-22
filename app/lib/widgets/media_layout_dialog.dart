import 'package:flutter/material.dart';

import '../data/media_layout.dart';

/// Shows what a folder import found wrong, once, after the import ran.
///
/// Called from each place a folder is picked - onboarding, the Settings
/// media row, and the media chooser - so the warning reads the same
/// everywhere: a list of the specific problems with the fix for each,
/// rather than a toast that names none.
Future<void> showMediaLayoutWarnings(
  BuildContext context,
  MediaLayoutReport? report,
) async {
  if (report == null) return;
  final List<String> warnings = report.warnings;
  if (warnings.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('About that folder'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final String warning in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 2, right: 8),
                      child: Icon(Icons.warning_amber_outlined, size: 18),
                    ),
                    Expanded(child: Text(warning)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
