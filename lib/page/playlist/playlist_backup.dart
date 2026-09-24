import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../services/imported_audio_store.dart';
import 'playlist_models.dart';

class BackupSong {
  final String name;
  final String? digest;

  const BackupSong({required this.name, required this.digest});

  Map<String, Object?> toJson() => {'name': name, 'sha256': digest};
}

class BackupPlaylist {
  final String id;
  final String name;
  final List<BackupSong> songs;

  const BackupPlaylist({
    required this.id,
    required this.name,
    required this.songs,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'songs': songs.map((song) => song.toJson()).toList(),
  };
}

class PlaylistRestorePlan {
  final List<Playlist> playlists;
  final int matchedSongs;
  final int missingSongs;

  const PlaylistRestorePlan({
    required this.playlists,
    required this.matchedSongs,
    required this.missingSongs,
  });
}

/// A portable playlist manifest. Music files and absolute device paths stay out.
class PlaylistBackup {
  static const format = 'myune-playlists';
  static const version = 1;
  static final _safeId = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');
  static final _digest = RegExp(r'^[a-f0-9]{64}$');

  final List<BackupPlaylist> playlists;

  const PlaylistBackup(this.playlists);

  int get songCount =>
      playlists.fold(0, (total, item) => total + item.songs.length);

  Set<String> get requiredDigests => {
    for (final playlist in playlists)
      for (final song in playlist.songs)
        if (song.digest != null) song.digest!,
  };

  static Future<PlaylistBackup> fromPlaylists(
    List<Playlist> playlists,
    ImportedAudioStore store,
  ) async {
    final digestCache = <String, String?>{};
    final backupPlaylists = <BackupPlaylist>[];
    for (final playlist in playlists) {
      final songs = <BackupSong>[];
      for (final filePath in playlist.songFilePaths) {
        final fileName = p.basename(filePath);
        final managedName = RegExp(r'^[a-f0-9]{64}_(.+)$').firstMatch(fileName);
        final originalName = managedName?.group(1) ?? fileName;
        final digest = digestCache.containsKey(filePath)
            ? digestCache[filePath]
            : await _digestForPath(filePath, store);
        digestCache[filePath] = digest;
        songs.add(BackupSong(name: originalName, digest: digest));
      }
      backupPlaylists.add(
        BackupPlaylist(id: playlist.id, name: playlist.name, songs: songs),
      );
    }
    return PlaylistBackup(backupPlaylists);
  }

  static Future<String?> _digestForPath(
    String filePath,
    ImportedAudioStore store,
  ) async {
    if (!await File(filePath).exists()) return null;
    return store.digestOf(filePath);
  }

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'format': format,
    'version': version,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'playlists': playlists.map((item) => item.toJson()).toList(),
  });

  factory PlaylistBackup.decode(String text) {
    final Object? root;
    try {
      root = jsonDecode(text);
    } catch (_) {
      throw const FormatException('备份文件不是有效的 JSON');
    }
    if (root is! Map<String, dynamic> ||
        root['format'] != format ||
        root['version'] != version ||
        root['playlists'] is! List) {
      throw const FormatException('备份格式或版本不受支持');
    }

    final rawPlaylists = root['playlists'] as List;
    if (rawPlaylists.length > 1000) {
      throw const FormatException('备份中的歌单数量超出限制');
    }
    final ids = <String>{};
    final parsed = <BackupPlaylist>[];
    var totalSongs = 0;
    for (final raw in rawPlaylists) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('歌单数据不完整');
      }
      final id = raw['id'];
      final name = raw['name'];
      final rawSongs = raw['songs'];
      if (id is! String ||
          !_safeId.hasMatch(id) ||
          !ids.add(id) ||
          name is! String ||
          name.trim().isEmpty ||
          name.length > 200 ||
          rawSongs is! List) {
        throw const FormatException('歌单名称或编号无效');
      }
      totalSongs += rawSongs.length;
      if (totalSongs > 100000) {
        throw const FormatException('备份中的歌曲数量超出限制');
      }
      final songs = <BackupSong>[];
      for (final rawSong in rawSongs) {
        if (rawSong is! Map<String, dynamic>) {
          throw const FormatException('歌曲数据不完整');
        }
        final songName = rawSong['name'];
        final digest = rawSong['sha256'];
        if (songName is! String ||
            songName.isEmpty ||
            songName.length > 255 ||
            (digest != null &&
                (digest is! String || !_digest.hasMatch(digest)))) {
          throw const FormatException('歌曲名称或指纹无效');
        }
        songs.add(BackupSong(name: songName, digest: digest as String?));
      }
      parsed.add(BackupPlaylist(id: id, name: name, songs: songs));
    }
    return PlaylistBackup(parsed);
  }

  PlaylistRestorePlan planRestore(
    List<Playlist> existing,
    Map<String, String> availableByDigest,
  ) {
    final result = [
      for (final playlist in existing)
        Playlist(
          id: playlist.id,
          name: playlist.name,
          isDefault: playlist.isDefault,
          songFilePaths: List.of(playlist.songFilePaths),
          currentPlayingIndex: playlist.currentPlayingIndex,
          isFolderBased: playlist.isFolderBased,
          folderPaths: List.of(playlist.folderPaths),
        ),
    ];
    var matched = 0;
    var missing = 0;
    for (final backupPlaylist in playlists) {
      var targetIndex = result.indexWhere(
        (item) => item.id == backupPlaylist.id,
      );
      if (targetIndex < 0) {
        var name = backupPlaylist.name;
        if (result.any((item) => item.name == name)) name = '$name (导入)';
        result.add(Playlist(id: backupPlaylist.id, name: name));
        targetIndex = result.length - 1;
      }
      final target = result[targetIndex];
      for (final song in backupPlaylist.songs) {
        final path = availableByDigest[song.digest];
        if (path == null) {
          missing++;
        } else {
          matched++;
          if (!target.songFilePaths.contains(path)) {
            target.songFilePaths.add(path);
          }
        }
      }
    }
    return PlaylistRestorePlan(
      playlists: result,
      matchedSongs: matched,
      missingSongs: missing,
    );
  }
}
