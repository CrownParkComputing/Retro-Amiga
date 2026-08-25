import 'dart:async';

import 'package:flutter/material.dart';

typedef ImportProgressUpdate =
    void Function(String message, {int? done, int? total});

/// Keeps a large Storage Access Framework import visibly alive.
///
/// Android has to enumerate the selected tree before it knows how many files
/// there are. That first phase is therefore indeterminate; copying switches to
/// a real fraction as soon as the total is known. The dialog cannot be
/// dismissed halfway through a batch, which would make a still-running import
/// look cancelled and allow a second one to start over it.
class ImportProgressDialog {
  const ImportProgressDialog._();

  static Future<T> run<T>(
    BuildContext context, {
    required String title,
    String initialMessage = 'Scanning folders…',
    required Future<T> Function(ImportProgressUpdate update) operation,
  }) async {
    final ValueNotifier<_ImportProgress> progress =
        ValueNotifier<_ImportProgress>(_ImportProgress(initialMessage));
    final Completer<BuildContext> ready = Completer<BuildContext>();

    final Future<void> dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        if (!ready.isCompleted) ready.complete(dialogContext);
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(title),
            content: ValueListenableBuilder<_ImportProgress>(
              valueListenable: progress,
              builder: (BuildContext context, _ImportProgress value, _) {
                final double? fraction = value.total == null || value.total == 0
                    ? null
                    : (value.done ?? 0) / value.total!;
                return SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(value.message),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: fraction),
                      if (value.total != null && value.total! > 0) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          '${value.done ?? 0} of ${value.total}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
    final BuildContext dialogContext = await ready.future;

    try {
      return await operation((String message, {int? done, int? total}) {
        progress.value = _ImportProgress(message, done: done, total: total);
      });
    } finally {
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      await dialog;
      progress.dispose();
    }
  }
}

class _ImportProgress {
  const _ImportProgress(this.message, {this.done, this.total});

  final String message;
  final int? done;
  final int? total;
}
