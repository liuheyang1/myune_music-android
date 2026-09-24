import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_manager.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';

void main() {
  late Directory sandbox;
  late PlaylistManager manager;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('myune_manager_test_');
    manager = PlaylistManager(rootDirectory: sandbox);
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('saves and reloads playlist membership', () async {
    await manager.savePlaylists([
      Playlist(id: 'test-list', name: '收藏', songFilePaths: ['one.mp3']),
    ]);
    await manager.savePlaylists([
      Playlist(
        id: 'test-list',
        name: '收藏',
        songFilePaths: ['one.mp3', 'two.mp3'],
      ),
    ]);

    final loaded = await manager.loadPlaylists();
    expect(loaded.single.name, '收藏');
    expect(loaded.single.songFilePaths, ['one.mp3', 'two.mp3']);
    expect(
      sandbox.listSync().where((entry) => entry.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test('does not overwrite unreadable playlist metadata', () async {
    final metadata = File('${sandbox.path}/playlists_metadata.json');
    await metadata.writeAsString('{broken json');

    final loaded = await manager.loadPlaylists();
    expect(loaded.single.songFilePaths, isEmpty);
    expect(await metadata.readAsString(), '{broken json');
    expect(
      sandbox.listSync().where((entry) => entry.path.contains('.corrupt.')),
      isNotEmpty,
    );
  });
}
