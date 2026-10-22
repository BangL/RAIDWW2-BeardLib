# RAIDWW2-BeardLib
A large library that assists in mod creation.
- Script File Manipulation.
- Custom Job (raid) framework
- Modules Framework
- Easy ability to add content

## Documentation
There is no proper documentation for the Raid version yet,
however, most of the doc for the pd2 version should fit for now: [wiki](https://luffyyy.gitbook.io/beardlib)

## Download
You can download a stable release from modworkshop: https://modworkshop.net/mod/14924

## Dependencies
* [RAID-SuperBLT](https://modworkshop.net/mod/49744)

NOTE: RAIDWW2-BeardLib does NOT work with RaidBLT!

## Templates
You can find them here: https://github.com/ModWorkshop/BeardLib-Templates

## Mods that make use of RAID-BeardLib
* [BeardLib-Editor](https://github.com/RAIDModding/BeardLib-Editor) (not released yet)
* tba

## Custom jobs and operations
The `<job>` (a raid) and `<operation>` modules, their attributes and the migration from the PAYDAY 2 `<narrative>` module are described for map makers in the [BeardLib-Editor README](https://github.com/RAIDModding/BeardLib-Editor#custom-jobs) (`Custom jobs`, `Custom operations`, `Migrating from narratives`). The library implements them (`Modules/Raid/JobModule.lua`, `OperationModule.lua`, `LevelModule.lua`); the first version with them is 5.1, set `min_lib_ver="5.1"` in your `main.xml`.

## Profile guard
Custom raids and levels are kept out of the saved profile: whatever the game stores under the id of a custom job or level (statistics, progression, breadcrumbs, ...) is removed when the profile is saved, so it is not polluted with their names. Kills, experience and so on are counted as usual. The option `Profile guard` (BeardLib mods menu, on by default) turns it off.

## Multiplayer
Custom jobs can be played together if everyone has BeardLib (5.1 or newer):
* BeardLib announces itself (version) and the custom jobs it has in the join request (tokens in the dlcs string, nothing else changes for vanilla).
* A client without BeardLib is turned away by the host while a custom job is selected or running, with the vanilla "does not own this heist" reply. It is neither kicked nor banned and can join again later. The host cannot select a custom job while such a client is in the lobby, it gets a message instead.
* A client with BeardLib but without the job gets the job info when the host selects it and is asked to download it (ModWorkshop, needs the `AssetUpdates` of the map). The host starts the job once everyone has it. A client that joins a running job downloads it before the join request is sent (the host puts the job into the lobby data), and joins when the download is done.

