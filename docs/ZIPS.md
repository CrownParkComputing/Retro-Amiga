# The reference zips

The app's whole setup is zips dropped into its folder (Files → On My iPad →
Amiga-Retro), imported by the wizard's Scan or by any later launch. These are
the reference set, kept in `~/Documents/retro-zips` on the build machine -
none of them live in the repo - so a fresh device can be provisioned in one
drag:

| zip | contents | in git? |
|---|---|---|
| `amiga-kickstarts.zip` | Kickstart ROMs (1.3, 3.1 A1200/A4000/A600, CD32 + ext) | no — Commodore's |
| `amiga-whdload.zip` | five WHDLoad game archives | no — publishers' |
| `amiga-games.zip` | ADF floppies + LHA sample | no — publishers' |
| `amiga-cdrom.zip` | one CD32 title (CHD) | no — publisher's |
| `amiga-music.zip` | eight ProTracker modules | no — composers' |
| `amiga-whdload-enabler.zip` | WHDLoad, JST, AmiQuit, boot-data.zip, whdload_db.xml, skick `.RTB` tables | no — rebuilt from `app/assets/whdboot/`, which the repo does ship |

The enabler is the WHDLoad support set *minus* the Kickstarts: everything the
booter needs that may legally travel. On iOS the app installs the same files
from its own bundle, so the enabler exists for the platforms and installs that
arrive without them — and as the reference for what "WHDLoad-ready" means.

Rebuild any of these from a machine holding the collection: the zips are flat
(no folders), routed on import by extension — ROMs to Kickstarts, `.adf` to
Floppies, `.lha` to LHA, `.mod` to Music, CD images to CDROMs.
