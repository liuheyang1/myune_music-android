import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../page/playlist/playlist_content_notifier.dart';
import '../../page/playlist/playlist_backup.dart';
import '../../page/setting/playlist_cleaner.dart';
import '../../page/setting/settings_provider.dart';
import '../../page/setting/theme_selection_screen.dart';
import '../../services/notification_service.dart';
import '../../services/imported_audio_store.dart';
import '../../theme/theme_provider.dart';

class MobileSettingsPage extends StatelessWidget {
  const MobileSettingsPage({super.key});

  static const _appVersion = '0.9.3+1';

  void _setDynamicColor(BuildContext context, bool enabled) {
    final settings = context.read<SettingsProvider>();
    final theme = context.read<ThemeProvider>();
    final playlist = context.read<PlaylistContentNotifier>();

    settings.setUseDynamicColor(enabled);
    if (enabled) {
      playlist.extractAndApplyDynamicColor(playlist.currentSong?.albumArt);
    } else {
      theme.restoreLastManualColor();
    }
  }

  void _setLyricSource(BuildContext context, String primary) {
    final settings = context.read<SettingsProvider>();
    settings.setPrimaryLyricSource(primary);
    settings.setSecondaryLyricSource(primary == 'qq' ? 'netease' : 'qq');
  }

  void _showConflict(BuildContext context, String message) {
    context.read<NotificationService>().info(message);
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Myune Music',
      applicationVersion: 'v$_appVersion · Android',
      applicationIcon: Image.asset(
        'assets/images/icon/logo.png',
        width: 48,
        height: 48,
      ),
      applicationLegalese:
          '基于 xiaobaimc/myune_music（Apache License 2.0）改造。听歌房插画为本项目新生成。',
      children: const [
        SizedBox(height: 8),
        Text('本应用不附带音乐或专辑封面。源码和素材来源见仓库说明。'),
      ],
    );
  }

  Future<void> _exportPlaylists(BuildContext context) async {
    final notice = context.read<NotificationService>();
    final current = context.read<PlaylistContentNotifier>();
    try {
      notice.info('正在生成歌单备份…');
      final backup = await PlaylistBackup.fromPlaylists(
        current.playlists,
        ImportedAudioStore(),
      );
      final saved = await FilePicker.platform.saveFile(
        fileName: 'myune-playlists.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(backup.encode())),
      );
      if (saved != null) notice.info('歌单备份已保存，不包含音乐文件');
    } catch (error) {
      notice.error('导出失败：$error');
    }
  }

  Future<void> _importPlaylists(BuildContext context) async {
    final notice = context.read<NotificationService>();
    final current = context.read<PlaylistContentNotifier>();
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      if (file.path == null || file.size > 8 * 1024 * 1024) {
        throw const FormatException('备份文件过大');
      }
      final contents = await File(file.path!).readAsString();
      final backup = PlaylistBackup.decode(contents);
      if (!context.mounted) return;

      final chooseAudio = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('恢复歌单'),
          content: Text(
            '找到 ${backup.playlists.length} 个歌单、${backup.songCount} 首歌曲记录。'
            '备份不包含音乐文件；换机后请重新选择音乐文件进行匹配。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('使用已有音乐'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('选择音乐文件'),
            ),
          ],
        ),
      );
      if (chooseAudio == null) return;

      final store = ImportedAudioStore();
      final available = await store.existingByDigest();
      final selected = <String, String>{};
      if (chooseAudio) {
        final audio = await FilePicker.platform.pickFiles(
          type: FileType.audio,
          allowMultiple: true,
        );
        if (audio == null) return;
        notice.info('正在匹配音乐文件…');
        for (final candidate in audio.files) {
          if (candidate.path == null) continue;
          final digest = await store.digestOf(candidate.path!);
          if (backup.requiredDigests.contains(digest) &&
              !available.containsKey(digest)) {
            selected[digest] = candidate.path!;
          }
        }
      }
      final preview = backup.planRestore(current.playlists, {
        ...available,
        ...selected,
      });
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认恢复'),
          content: Text(
            '可匹配 ${preview.matchedSongs} 首，尚未找到 ${preview.missingSongs} 首。'
            '已有歌单会保留，匹配到的歌曲会合并进去。继续吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      notice.info('正在保存歌单…');
      for (final entry in selected.entries) {
        available[entry.key] = await store.persist(entry.value);
      }
      final plan = backup.planRestore(current.playlists, available);
      await current.applyRestoredPlaylists(plan);
      notice.info('已恢复 ${plan.matchedSongs} 首；未找到 ${plan.missingSongs} 首');
    } on FormatException catch (error) {
      notice.error('无法读取备份：${error.message}');
    } catch (error) {
      notice.error('恢复失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final theme = context.watch<ThemeProvider>();
    final playlist = context.read<PlaylistContentNotifier>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          const _SectionTitle('外观'),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const Expanded(child: Text('主题模式')),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                        ),
                      ],
                      selected: {theme.themeMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        if (selection.isNotEmpty) {
                          context.read<ThemeProvider>().setThemeMode(
                            selection.first,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const ThemeSelectionScreen(),
              SwitchListTile(
                title: const Text('跟随专辑封面配色'),
                subtitle: const Text('播放歌曲时自动调整应用主题颜色'),
                value: settings.useDynamicColor,
                onChanged: (value) => _setDynamicColor(context, value),
              ),
            ],
          ),
          const _SectionTitle('歌词'),
          _SettingsCard(
            children: [
              SwitchListTile(
                title: const Text('在线补充歌词'),
                subtitle: const Text('本地和内嵌歌词都不存在时再联网搜索'),
                value: settings.enableOnlineLyrics,
                onChanged: settings.setEnableOnlineLyrics,
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: settings.enableOnlineLyrics ? 1 : 0.45,
                child: IgnorePointer(
                  ignoring: !settings.enableOnlineLyrics,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Row(
                      children: [
                        const Expanded(child: Text('优先歌词源')),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'qq', label: Text('企鹅')),
                            ButtonSegment(value: 'netease', label: Text('网抑')),
                            ButtonSegment(value: 'kugou', label: Text('库狗')),
                          ],
                          selected: {settings.primaryLyricSource},
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) {
                            if (selection.isNotEmpty) {
                              _setLyricSource(context, selection.first);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const _SectionTitle('播放'),
          _SettingsCard(
            children: [
              SwitchListTile(
                title: const Text('平衡歌曲音量'),
                subtitle: const Text('将不同歌曲的响度统一到接近的水平'),
                value: settings.enableLoudness,
                onChanged: (value) {
                  if (value && settings.enableReplayGain) {
                    _showConflict(context, '请先关闭重放增益');
                    return;
                  }
                  context.read<SettingsProvider>().setEnableLoudness(value);
                  playlist.updateLoudnessSettings();
                },
              ),
              SwitchListTile(
                title: const Text('使用重放增益标签'),
                subtitle: const Text('仅对已经包含 ReplayGain 标签的歌曲生效'),
                value: settings.enableReplayGain,
                onChanged: (value) {
                  if (value && settings.enableLoudness) {
                    _showConflict(context, '请先关闭歌曲音量平衡');
                    return;
                  }
                  context.read<SettingsProvider>().setEnableReplayGain(value);
                  playlist.updateReplayGainSettings();
                },
              ),
              SwitchListTile(
                title: const Text('无缝队列'),
                subtitle: const Text('尽量消除连续歌曲切换时的短暂停顿'),
                value: settings.enableGaplessPlayback,
                onChanged: (value) {
                  context.read<SettingsProvider>().setEnableGaplessPlayback(
                    value,
                  );
                  playlist.updateGaplessMode(value);
                },
              ),
            ],
          ),
          const _SectionTitle('歌曲库'),
          _SettingsCard(
            children: [
              SwitchListTile(
                title: const Text('允许选择任意格式'),
                subtitle: const Text('仅在确认文件能够正常播放时开启'),
                value: settings.allowAnyFormat,
                onChanged: settings.setAllowAnyFormat,
              ),
              SwitchListTile(
                title: const Text('忽略部分解码错误'),
                subtitle: const Text('文件能够播放但仍报告格式错误时使用'),
                value: settings.ignorePlaybackErrors,
                onChanged: settings.setIgnorePlaybackErrors,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: PlaylistCleaner(notifier: playlist),
              ),
              ListTile(
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('导出歌单备份'),
                subtitle: const Text('保存歌单结构和歌曲指纹，不包含音乐文件'),
                onTap: () => _exportPlaylists(context),
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('恢复歌单备份'),
                subtitle: const Text('重新选择音乐文件，按内容匹配后合并'),
                onTap: () => _importPlaylists(context),
              ),
            ],
          ),
          const _SectionTitle('关于'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Myune Music Android'),
              subtitle: const Text('版本 v$_appVersion'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showAbout(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
