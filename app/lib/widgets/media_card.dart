import 'package:flutter/material.dart';

import '../data/file_category.dart';
import '../data/media_library.dart';
import '../theme/amiga_theme.dart';

/// One file in the library grid.
///
/// There is no box art to show - nothing on the device carries any - so the
/// card leads with the thing that does distinguish these files: what kind of
/// media it is, in the colour of that kind. A wall of identical grey cards
/// with only a filename would be harder to read, not more honest.
class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.file, required this.onTap});

  final MediaFile file;
  final VoidCallback onTap;

  static Color colourFor(FileCategory category) {
    switch (category) {
      case FileCategory.floppies:
        return AmigaColors.workbenchBlue;
      case FileCategory.whdloadGames:
        return const Color(0xFF7C3AED);
      case FileCategory.hardDrives:
        return const Color(0xFF0E7C66);
      case FileCategory.cdImages:
        return const Color(0xFFB45309);
      case FileCategory.archives:
        return const Color(0xFF4B5563);
      case FileCategory.roms:
        return AmigaColors.tickRed;
      case FileCategory.music:
        return const Color(0xFF9D174D);
    }
  }

  static IconData iconFor(FileCategory category) {
    switch (category) {
      case FileCategory.floppies:
        return Icons.save_outlined; // a 3.5" disk, which is the save icon
      case FileCategory.whdloadGames:
        return Icons.inventory_2_outlined;
      case FileCategory.hardDrives:
        return Icons.storage_outlined;
      case FileCategory.cdImages:
        return Icons.album_outlined;
      case FileCategory.archives:
        return Icons.folder_zip_outlined;
      case FileCategory.roms:
        return Icons.memory_outlined;
      case FileCategory.music:
        return Icons.music_note_outlined;
    }
  }

  String get _extension {
    final int dot = file.name.lastIndexOf('.');
    return dot < 0 ? '' : file.name.substring(dot + 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final Color colour = colourFor(file.category);

    return Material(
      color: AmigaColors.card,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      colour,
                      Color.lerp(colour, Colors.black, 0.45)!,
                    ],
                  ),
                ),
                child: Stack(
                  children: <Widget>[
                    Center(
                      child: Icon(
                        iconFor(file.category),
                        size: 34,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _extension,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    file.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      color: AmigaColors.text,
                    ),
                  ),
                  if (file.folder.isNotEmpty)
                    Text(
                      file.folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AmigaColors.textDim,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
