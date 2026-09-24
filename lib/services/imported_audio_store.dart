import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps audio selected through Android's document picker out of its cache.
class ImportedAudioStore {
  static final _managedName = RegExp(r'^([a-f0-9]{64})_(.+)$');
  final Directory? _directoryOverride;

  ImportedAudioStore({Directory? directory}) : _directoryOverride = directory;

  Future<Directory> get directory async {
    if (_directoryOverride != null) {
      await _directoryOverride.create(recursive: true);
      return _directoryOverride;
    }
    final support = await getApplicationSupportDirectory();
    final result = Directory(
      p.join(support.path, 'myune_music', 'imported_audio'),
    );
    await result.create(recursive: true);
    return result;
  }

  Future<String> digestOf(String filePath) async {
    return (await sha256.bind(File(filePath).openRead()).first).toString();
  }

  Future<String> persist(String sourcePath, {String? originalName}) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException(
        'Selected audio is no longer available',
        sourcePath,
      );
    }

    final managedDirectory = await directory;
    if (p.isWithin(managedDirectory.path, source.absolute.path)) {
      return p.normalize(source.absolute.path);
    }

    final digest = await digestOf(sourcePath);
    final rawName = p.basename(originalName ?? sourcePath);
    final safeName = rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final destination = File(
      p.join(
        managedDirectory.path,
        '${digest}_${safeName.isEmpty ? 'audio' : safeName}',
      ),
    );
    if (await destination.exists()) return p.normalize(destination.path);

    final temporary = File('${destination.path}.part');
    try {
      await source.copy(temporary.path);
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return p.normalize(destination.path);
  }

  Future<Map<String, String>> existingByDigest() async {
    final result = <String, String>{};
    final managedDirectory = await directory;
    await for (final entity in managedDirectory.list()) {
      if (entity is! File) continue;
      final match = _managedName.firstMatch(p.basename(entity.path));
      if (match != null) result[match.group(1)!] = p.normalize(entity.path);
    }
    return result;
  }

  String? digestFromManagedPath(String path) {
    return _managedName.firstMatch(p.basename(path))?.group(1);
  }
}
