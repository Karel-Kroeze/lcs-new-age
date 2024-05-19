import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:lcs_new_age/common_display/common_display.dart';
import 'package:lcs_new_age/daily/recruitment.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/title_screen/launch_game.dart';
import 'package:lcs_new_age/title_screen/title_screen.dart';
import 'package:lcs_new_age/utils/colors.dart';
import 'package:lcs_new_age/utils/interface_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'save_load.g.dart';

Future<void> autoSaveGame() async {
  //Stopwatch stopwatch = Stopwatch()..start();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString("gameVersion${gameState.uniqueGameId}", gameVersion);
  await prefs.setString(
      "savedGame${gameState.uniqueGameId}", jsonEncode(gameState.toJson()));
  await prefs.setString(
      "lastPlayed${gameState.uniqueGameId}", DateTime.now().toIso8601String());
  await prefs.setInt("lastGameId", gameState.uniqueGameId);
  final List<String>? saveGameIds = prefs.getStringList("savedGameIds");
  if (saveGameIds == null) {
    await prefs
        .setStringList("savedGameIds", [gameState.uniqueGameId.toString()]);
  } else {
    if (!saveGameIds.contains(gameState.uniqueGameId.toString())) {
      saveGameIds.add(gameState.uniqueGameId.toString());
    }
    await prefs.setStringList("savedGameIds", saveGameIds);
  }
  //debugPrint("Saved game in ${stopwatch.elapsedMilliseconds}ms");
}

@JsonSerializable()
class SaveFile {
  SaveFile({
    required this.version,
    required this.saveData,
    required this.gameId,
    required this.lastPlayed,
    this.gameState,
  });
  factory SaveFile.fromJson(Map<String, dynamic> json) {
    String version = json["version"];
    if (compareVersionStrings(version, "1.0.2") < 0) {
      json["saveData"] = jsonDecode(json["saveData"]);
    }
    return _$SaveFileFromJson(json);
  }
  Map<String, dynamic> toJson() => _$SaveFileToJson(this);

  final String gameId;
  final String version;
  final Map<String, dynamic> saveData;
  final DateTime? lastPlayed;
  @JsonKey(includeToJson: false, includeFromJson: false)
  final GameState? gameState;
}

Future<bool> loadGameMenu() async {
  while (true) {
    List<SaveFile> saveFiles = await loadGameList();
    if (saveFiles.isEmpty) {
      return false;
    }
    int selectedGame = -1;
    bool import = false;
    bool newGame = false;
    await pagedInterface(
        count: saveFiles.length,
        headerPrompt: "Liberal Save Game Management System",
        headerKey: {
          4: "IN GAME DATE",
          20: "LCS LEADER",
          50: "LAST PLAYED",
          70: "VERSION",
        },
        footerPrompt:
            "Plus (+) to Import a save.  Minus (-) to found a new Liberal Crime Squad.",
        lineBuilder: (y, key, index) {
          final SaveFile saveFile = saveFiles[index];
          if (saveFile.gameState == null) {
            setColor(red);
          } else {
            setColor(lightGray);
          }
          DateTime? lastPlayed = saveFile.lastPlayed?.toLocal();
          String version = saveFile.version;
          String inGameDate;
          String founder;
          String lastPlayedStr;
          if (lastPlayed != null) {
            lastPlayedStr =
                "${getMonthShort(lastPlayed.month)} ${lastPlayed.day}, ${lastPlayed.year}";
          } else {
            lastPlayedStr = "Unknown";
          }
          if (saveFile.gameState != null) {
            inGameDate =
                "${getMonthShort(saveFile.gameState!.date.month)} ${saveFile.gameState!.date.day}, ${saveFile.gameState!.date.year}";

            founder = saveFile.gameState!.lcs.pool
                    .firstWhereOrNull(
                        (e) => e.hireId == null && e.align == Alignment.liberal)
                    ?.name ??
                "Unknown";
          } else {
            inGameDate = "Error";
            founder = "Error - Crash Expected";
          }
          mvaddstr(y, 0, "$key - ");
          mvaddstr(y, 4, inGameDate);
          mvaddstr(y, 20, founder);
          mvaddstr(y, 50, lastPlayedStr);
          mvaddstr(y, 70, version);
        },
        onChoice: (index) {
          selectedGame = index;
        },
        onOtherKey: (key) {
          if (key == Key.plus) {
            import = true;
            return true;
          } else if (key == Key.minus) {
            newGame = true;
            return true;
          }
          return false;
        });
    if (import) {
      await importSave();
      continue;
    }
    SaveFile? selectedSave = selectedGame >= 0 ? saveFiles[selectedGame] : null;
    if (selectedSave != null) {
      if (await loadGame(selectedSave)) {
        return true;
      }
    } else if (newGame) {
      return false;
    }
  }
}

Future<bool> loadGame(SaveFile selectedSave) async {
  String broken =
      selectedSave.gameState != null ? "" : "Conservatively Broken ";
  erase();
  mvaddstrc(1, 1, lightGray, "Manage ${broken}Saved Game");
  mvaddstr(3, 1,
      "L - ${selectedSave.gameState != null ? "Load Game" : "Load Game (Crash Report Expected)"}");
  mvaddstr(4, 1, "D - Delete Save");
  mvaddstr(5, 1, "B - Backup Save");
  mvaddstr(7, 1, "Press the key for the action you want to take.");
  while (true) {
    int c = await getKey();
    if (c == Key.l) {
      return await loadGameFromSave(selectedSave);
    } else if (c == Key.d) {
      await deleteSave(selectedSave);
      return false;
    } else if (c == Key.b) {
      await backupSave(selectedSave);
    } else if (c == Key.q || isBackKey(c)) {
      return false;
    }
  }
}

Future<bool> loadGameFromSave(SaveFile selectedSave) async {
  if (selectedSave.gameState == null) {
    debugPrint("Generating crash report from ${selectedSave.version}");
    gameState = GameState.fromJson(selectedSave.saveData);
  } else {
    debugPrint("Loading game from ${selectedSave.version}");
    gameState = selectedSave.gameState!;
  }
  applyBugFixes(selectedSave.version);
  return true;
}

Future<void> deleteSave(SaveFile selectedSave) async {
  erase();
  mvaddstrc(1, 1, lightGray, "Delete Saved Game");
  mvaddstr(3, 1, "Are you SURE you want to delete this saved game?");
  mvaddstr(5, 1, "Y - Yes, delete the save.");
  mvaddstr(6, 1, "N - No, do not delete the save.");
  while (true) {
    int c = await getKey();
    if (c == Key.y) {
      await deleteSaveGameId(selectedSave.gameId);
      return;
    } else if (c == Key.n) {
      return;
    }
  }
}

Future<void> deleteSaveGameId(String gameId) async {
  final prefs = await SharedPreferences.getInstance();
  final List<String>? saveGameIds = prefs.getStringList("savedGameIds");
  if (saveGameIds != null) {
    saveGameIds.remove(gameId);
    await prefs.setStringList("savedGameIds", saveGameIds);
  }
  await prefs.remove("gameVersion$gameId");
  await prefs.remove("savedGame$gameId");
  await prefs.remove("lastPlayed$gameId");
}

Future<void> backupSave(SaveFile selectedSave) async {
  String json = jsonEncode(selectedSave.toJson());
  await FileSaver.instance.saveFile(
    bytes: const Utf8Encoder().convert(json),
    name: "lcsna_backup_${selectedSave.gameId}.json",
  );
}

Future<SaveFile?> importSave() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ["json"],
    withData: true,
    dialogTitle: "Select an LCS: New Age Save File",
  );
  if (result != null) {
    Uint8List fileBytes = result.files.single.bytes!;
    String json = const Utf8Decoder().convert(fileBytes);
    try {
      final Map<String, dynamic> saveData = jsonDecode(json);
      final SaveFile saveFile = SaveFile.fromJson(saveData);
      await saveGameFile(saveFile);
      erase();
      mvaddstrc(1, 1, lightGray, "Save imported successfully.");
      mvaddstr(3, 1, "Press any key to continue.");
      await getKey();
      return saveFile;
    } catch (e) {
      erase();
      mvaddstrc(1, 1, lightGray, "Error importing save: $e");
      if (e is Error) {
        mvaddstr(3, 1, "Press R to Generate a Crash Report");
        mvaddstr(4, 1, "Any other key to return to the title screen.");
      } else {
        mvaddstr(3, 1, "Press any key to return to the title screen.");
      }
      int c = await getKey();
      if (c == Key.r && e is Error) await errorScreen(e);
      return null;
    }
  } else {
    return null;
  }
}

Future<void> saveGameFile(SaveFile saveFile) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString("gameVersion${saveFile.gameId}", saveFile.version);
  await prefs.setString(
      "savedGame${saveFile.gameId}", jsonEncode(saveFile.saveData));
  await prefs.setString(
      "lastPlayed${saveFile.gameId}",
      saveFile.lastPlayed?.toIso8601String() ??
          DateTime.now().toIso8601String());
  final List<String>? saveGameIds = prefs.getStringList("savedGameIds");
  if (saveGameIds == null) {
    await prefs.setStringList("savedGameIds", [saveFile.gameId]);
  } else {
    if (!saveGameIds.contains(saveFile.gameId)) {
      saveGameIds.add(saveFile.gameId);
    }
    await prefs.setStringList("savedGameIds", saveGameIds);
  }
}

Future<List<SaveFile>> loadGameList() async {
  //Stopwatch stopwatch = Stopwatch()..start();
  final prefs = await SharedPreferences.getInstance();
  final List<String> savedGameIds = prefs.getStringList("savedGameIds") ?? [];
  //debugPrint("Loaded game list in ${stopwatch.elapsedMilliseconds}ms");
  List<SaveFile> saveFiles = [];
  for (int i = 0; i < savedGameIds.length; i++) {
    final String? version = prefs.getString("gameVersion${savedGameIds[i]}");
    final String? savedGame = prefs.getString("savedGame${savedGameIds[i]}");
    final String? lastPlayed = prefs.getString("lastPlayed${savedGameIds[i]}");
    final DateTime? lastPlayedDate =
        lastPlayed != null ? DateTime.tryParse(lastPlayed) : null;
    try {
      final GameState? gameState =
          savedGame != null ? GameState.fromJson(jsonDecode(savedGame)) : null;
      saveFiles.add(SaveFile(
        version: version ?? "ERROR",
        saveData: jsonDecode(savedGame ?? ""),
        lastPlayed: lastPlayedDate,
        gameId: savedGameIds[i],
        gameState: gameState,
      ));
    } catch (e) {
      debugPrint("Error loading save game $i: $e");
      saveFiles.add(SaveFile(
        version: version ?? "ERROR",
        saveData: jsonDecode(savedGame ?? ""),
        gameId: savedGameIds[i],
        lastPlayed: lastPlayedDate,
      ));
    }
  }
  return saveFiles;
}

Future<void> deleteSaveGame() async {
  await deleteSaveGameId(gameState.uniqueGameId.toString());
}

int compareVersionStrings(String a, String b) {
  List<int> aParts = a.split(".").map(int.parse).toList();
  List<int> bParts = b.split(".").map(int.parse).toList();
  for (int i = 0; i < aParts.length; i++) {
    if (i >= bParts.length) {
      return 1;
    }
    if (aParts[i] > bParts[i]) {
      return 1;
    } else if (aParts[i] < bParts[i]) {
      return -1;
    }
  }
  if (aParts.length < bParts.length) {
    return -1;
  }
  return 0;
}

void applyBugFixes(String version) {
  gameState.uniqueCreatures.syncWithPool();
  for (RecruitmentSession recruitmentSession in gameState.recruitmentSessions) {
    recruitmentSession.recruiter = pool.firstWhere(
        (p) => p.id == recruitmentSession.recruiterId,
        orElse: () => pool[0]);
  }
  if (compareVersionStrings(version, "1.0.5") < 0) {
    // Fix for the bug where CCS safehouses don't get marked as such if you
    // play in "We Didn't Start The Fire" mode
    if (ccsActive) {
      for (Site s in sites.where((s) =>
          s.controller == SiteController.unaligned &&
          [SiteType.barAndGrill, SiteType.bombShelter, SiteType.bunker]
              .contains(s.type))) {
        s.controller = SiteController.ccs;
      }
    }
  }
  // Fix ceo and president locations
  if (!uniqueCreatures.ceo.kidnapped &&
      !uniqueCreatures.ceo.missing &&
      uniqueCreatures.ceo.align == Alignment.conservative &&
      uniqueCreatures.ceo.site?.type != SiteType.ceoHouse) {
    uniqueCreatures.ceo.location =
        sites.firstWhere((s) => s.type == SiteType.ceoHouse);
    uniqueCreatures.ceo.workLocation = uniqueCreatures.ceo.location;
  }
  if (!uniqueCreatures.president.kidnapped &&
      !uniqueCreatures.president.missing &&
      uniqueCreatures.president.align == Alignment.conservative &&
      uniqueCreatures.president.site?.type != SiteType.whiteHouse) {
    uniqueCreatures.president.location =
        sites.firstWhere((s) => s.type == SiteType.whiteHouse);
    uniqueCreatures.president.workLocation = uniqueCreatures.president.location;
  }
}
