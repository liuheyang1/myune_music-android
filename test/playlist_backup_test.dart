import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_backup.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/services/imported_audio_store.dart';

void main() {
  late Directory sandbox;
  late ImportedAudioStore store;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('myune_backup_test_');
    store = ImportedAudioStore(directory: Directory('${sandbox.path}/managed'));
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('picked audio survives deletion of the picker cache copy', () async {
    final cached = File('${sandbox.path}/picker/song.mp3');
    await cached.parent.create(recursive: true);
    await cached.writeAsBytes([1, 2, 3, 4]);

    final saved = await store.persist(cached.path, originalName: 'song.mp3');
    await cached.delete();
    expect(await File(saved).readAsBytes(), [1, 2, 3, 4]);
    expect(await store.persist(saved), saved);
    expect((await store.existingByDigest()).values, contains(saved));
  });

  test('backup omits absolute paths and restores matching songs', () async {
    final cached = File('${sandbox.path}/picker/song.mp3');
    await cached.parent.create(recursive: true);
    await cached.writeAsBytes([10, 20, 30]);
    final saved = await store.persist(cached.path, originalName: 'song.mp3');
    final original = Playlist(
      id: 'playlist_1',
      name: '收藏',
      songFilePaths: [saved],
    );

    final backup = await PlaylistBackup.fromPlaylists([original], store);
    final encoded = backup.encode();
    expect(encoded, isNot(contains(sandbox.path)));
    final decoded = PlaylistBackup.decode(encoded);
    final plan = decoded.planRestore([], await store.existingByDigest());
    expect(plan.matchedSongs, 1);
    expect(plan.missingSongs, 0);
    expect(plan.playlists.single.songFilePaths, [saved]);
  });

  test('restore adds matches without deleting existing songs', () {
    const digest =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const backup = PlaylistBackup([
      BackupPlaylist(
        id: 'playlist_1',
        name: '收藏',
        songs: [
          BackupSong(name: 'matched.mp3', digest: digest),
          BackupSong(name: 'missing.mp3', digest: null),
        ],
      ),
    ]);
    final current = Playlist(
      id: 'playlist_1',
      name: '收藏',
      songFilePaths: ['already.mp3'],
    );

    final plan = backup.planRestore([current], {digest: 'new.mp3'});
    expect(plan.playlists.single.songFilePaths, ['already.mp3', 'new.mp3']);
    expect(current.songFilePaths, ['already.mp3']);
    expect(plan.matchedSongs, 1);
    expect(plan.missingSongs, 1);
  });

  test('rejects path traversal in an imported playlist id', () {
    const payload =
        '{"format":"myune-playlists","version":1,"playlists":['
        '{"id":"../outside","name":"bad","songs":[]}]}';
    expect(() => PlaylistBackup.decode(payload), throwsFormatException);
  });
}
