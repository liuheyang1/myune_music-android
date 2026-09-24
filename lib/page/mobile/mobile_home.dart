import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../mobile/settings/mobile_settings_page.dart';
import '../../widgets/immersive_scene_background.dart';
import '../../widgets/playbar.dart';
import '../all_songs/all_songs_page.dart';
import '../playlist/playlist_content_notifier.dart';
import '../playlist/playlist_content_widget.dart' show SongTileWidget;
import '../playlist/playlist_models.dart' show Song;
import '../song_detail_page.dart';
import '../song_list/album_list.dart';

class MobileHome extends StatefulWidget {
  const MobileHome({super.key});

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

enum _MobileDestination { home, library, nowPlaying, search, settings }

class _MobileHomeState extends State<MobileHome> {
  _MobileDestination _selectedDestination = _MobileDestination.home;

  void _selectDestination(_MobileDestination destination) {
    if (destination == _MobileDestination.nowPlaying) {
      final heroTag = _selectedDestination == _MobileDestination.home
          ? mobileListeningRoomHeroTag
          : mobileNowPlayingHeroTag;
      unawaited(_openNowPlayingPage(heroTag: heroTag));
      return;
    }
    if (_selectedDestination == destination) return;

    final notifier = context.read<PlaylistContentNotifier>();
    if (_selectedDestination == _MobileDestination.search) {
      notifier.stopSearch();
    }
    if (destination == _MobileDestination.search) {
      notifier.setActiveAllSongsView();
      notifier.startSearch();
    } else if (destination == _MobileDestination.library) {
      notifier.clearActiveDetailView();
    }

    setState(() => _selectedDestination = destination);
  }

  Future<void> _openNowPlayingPage({
    bool startInFocusMode = false,
    Object heroTag = mobileListeningRoomHeroTag,
  }) async {
    final notifier = context.read<PlaylistContentNotifier>();
    if (_selectedDestination == _MobileDestination.search) {
      notifier.stopSearch();
    }
    if (!mounted) return;

    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 520),
        reverseTransitionDuration: const Duration(milliseconds: 460),
        pageBuilder: (_, _, _) => SongDetailPage(
          heroTag: heroTag,
          startInFocusMode: startInFocusMode,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.12, 1, curve: Curves.easeOutCubic),
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(opacity: fade, child: child);
        },
      ),
    );
  }

  Widget _buildPage() {
    return KeyedSubtree(
      key: ValueKey(_selectedDestination),
      child: switch (_selectedDestination) {
        _MobileDestination.home => MobileListeningRoomPage(
          onShowMenu: _showDestinationMenu,
          onOpenLibrary: () => _selectDestination(_MobileDestination.library),
          onOpenNowPlaying: _openNowPlayingPage,
          onEnterFocusMode: () => _openNowPlayingPage(startInFocusMode: true),
        ),
        _MobileDestination.library => const MobileLibraryPage(),
        _MobileDestination.search => const MobileSearchPage(),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Future<void> _showDestinationMenu() async {
    final selected = await showModalBottomSheet<_MobileDestination>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        const destinations = [
          (_MobileDestination.home, Icons.home_outlined, '首页'),
          (_MobileDestination.library, Icons.library_music_outlined, '音乐库'),
          (_MobileDestination.nowPlaying, Icons.play_circle_outline, '正在播放'),
          (_MobileDestination.search, Icons.search, '搜索'),
          (_MobileDestination.settings, Icons.settings_outlined, '设置'),
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    '功能菜单',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                for (final destination in destinations)
                  ListTile(
                    leading: Icon(destination.$2),
                    title: Text(destination.$3),
                    trailing: destination.$1 == _selectedDestination
                        ? Icon(
                            Icons.check,
                            color: Theme.of(sheetContext).colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.of(sheetContext).pop(destination.$1),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      if (selected == _MobileDestination.settings) {
        await Navigator.of(context).push(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 360),
            reverseTransitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (_, _, _) => const MobileSettingsPage(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  );
                  return FadeTransition(
                    opacity: curved,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.035, 0),
                        end: Offset.zero,
                      ).animate(curved),
                      child: child,
                    ),
                  );
                },
          ),
        );
        return;
      }
      _selectDestination(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showPageHeader =
        _selectedDestination == _MobileDestination.library ||
        _selectedDestination == _MobileDestination.search;
    final pageTitle = _selectedDestination == _MobileDestination.search
        ? '搜索'
        : '音乐库';

    final isListeningRoom = _selectedDestination == _MobileDestination.home;
    final content = Column(
      children: [
        if (showPageHeader)
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _selectedDestination == _MobileDestination.search
                      ? Icons.search
                      : Icons.library_music,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  pageTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '功能菜单',
                  onPressed: _showDestinationMenu,
                  icon: const Icon(Icons.apps_rounded),
                ),
              ],
            ),
          ),
        Expanded(
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 340),
              reverseDuration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.985,
                      end: 1,
                    ).animate(animation),
                    alignment: Alignment.center,
                    child: child,
                  ),
                );
              },
              child: _buildPage(),
            ),
          ),
        ),
        if (!isListeningRoom)
          Playbar(
            albumArtHeroTag: mobileNowPlayingHeroTag,
            onOpenNowPlaying: () =>
                _openNowPlayingPage(heroTag: mobileNowPlayingHeroTag),
          ),
      ],
    );
    final pageContent = isListeningRoom
        ? ImmersiveSceneBackground(backdropOnly: true, child: content)
        : content;

    return PopScope(
      // MobileHome 的子页面不进入 Navigator 路由栈：返回手势先收起
      // 专辑详情，再从功能页面回到首页。
      canPop: _selectedDestination == _MobileDestination.home,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        final notifier = context.read<PlaylistContentNotifier>();
        final isAlbumDetail =
            _selectedDestination == _MobileDestination.library &&
            notifier.currentDetailViewContext == DetailViewContext.album;
        if (isAlbumDetail) {
          notifier.clearActiveDetailView();
          return;
        }

        if (_selectedDestination != _MobileDestination.home) {
          _selectDestination(_MobileDestination.home);
        }
      },
      child: ColoredBox(
        color: colorScheme.surface,
        child: SafeArea(child: pageContent),
      ),
    );
  }
}

class MobileListeningRoomPage extends StatelessWidget {
  final VoidCallback onShowMenu;
  final VoidCallback onOpenLibrary;
  final Future<void> Function() onOpenNowPlaying;
  final Future<void> Function() onEnterFocusMode;

  const MobileListeningRoomPage({
    super.key,
    required this.onShowMenu,
    required this.onOpenLibrary,
    required this.onOpenNowPlaying,
    required this.onEnterFocusMode,
  });

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final song = notifier.currentSong;

    Future<void> continueListening() async {
      if (song == null) {
        onOpenLibrary();
        return;
      } else if (!notifier.isPlaying) {
        await notifier.play();
      }
    }

    Future<void> openFocusMode() async {
      if (song == null) {
        onOpenLibrary();
        return;
      }
      await onEnterFocusMode();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.08),
            Colors.black.withValues(alpha: 0.16),
            Colors.black.withValues(alpha: 0.42),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.music_note_rounded, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '听歌房',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Myune Listening Room',
                        style: TextStyle(
                          color: Color(0xD9FFFFFF),
                          fontSize: 11,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '功能菜单',
                  onPressed: onShowMenu,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.24),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.apps_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Spacer(flex: 1),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const ImmersiveSceneBackground(
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          Hero(
                            tag: mobileListeningRoomHeroTag,
                            transitionOnUserGestures: true,
                            createRectTween: (begin, end) =>
                                MaterialRectCenterArcTween(
                                  begin: begin,
                                  end: end,
                                ),
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(15),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                key: const ValueKey('listening-room-album-art'),
                                onTap: song == null ? null : onOpenNowPlaying,
                                child: SizedBox(
                                  width: 74,
                                  height: 74,
                                  child:
                                      song?.albumArt != null &&
                                          song!.albumArt!.isNotEmpty
                                      ? Image.memory(
                                          song.albumArt!,
                                          fit: BoxFit.cover,
                                          gaplessPlayback: true,
                                        )
                                      : const Icon(
                                          Icons.music_note_rounded,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song?.title ?? '从一首歌开始',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  song == null
                                      ? '先选择一首歌'
                                      : '${song.artist} · ${song.album}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xD9FFFFFF),
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                FilledButton.icon(
                                  key: const ValueKey('listening-room-primary'),
                                  onPressed: continueListening,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF23496B),
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                  ),
                                  icon: Icon(
                                    song != null && notifier.isPlaying
                                        ? Icons.graphic_eq_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 19,
                                  ),
                                  label: Text(
                                    song == null
                                        ? '音乐库'
                                        : notifier.isPlaying
                                        ? '正在播放'
                                        : '继续播放',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ListeningRoomAction(
                        key: const ValueKey('listening-room-focus'),
                        icon: Icons.fullscreen_rounded,
                        tooltip: '专注模式',
                        onTap: openFocusMode,
                      ),
                      const SizedBox(height: 10),
                      _ListeningRoomAction(
                        key: const ValueKey('listening-room-library'),
                        icon: Icons.library_music_outlined,
                        tooltip: '音乐库',
                        onTap: onOpenLibrary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ListeningRoomAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final FutureOr<void> Function()? onTap;

  const _ListeningRoomAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.black.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 68,
              height: 60,
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

class _LibrarySection {
  final String label;
  final Widget child;
  final VoidCallback onSelected;

  const _LibrarySection({
    required this.label,
    required this.child,
    required this.onSelected,
  });
}

class MobileLibraryPage extends StatelessWidget {
  const MobileLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.read<PlaylistContentNotifier>();
    final sections = <_LibrarySection>[
      _LibrarySection(
        label: '专辑',
        child: const AlbumList(showLyricHeader: false),
        onSelected: notifier.clearActiveDetailView,
      ),
      _LibrarySection(
        label: '全部歌曲',
        child: const AllSongsPage(),
        onSelected: notifier.setActiveAllSongsView,
      ),
    ];

    return DefaultTabController(
      key: ValueKey(sections.map((section) => section.label).join('|')),
      length: sections.length,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              isScrollable: sections.length > 4,
              onTap: (index) {
                notifier.stopSearch();
                sections[index].onSelected();
              },
              tabs: [
                for (final section in sections)
                  Tab(height: 44, text: section.label),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [for (final section in sections) section.child],
            ),
          ),
        ],
      ),
    );
  }
}

class MobileSearchPage extends StatefulWidget {
  const MobileSearchPage({super.key});

  @override
  State<MobileSearchPage> createState() => _MobileSearchPageState();
}

class _MobileSearchPageState extends State<MobileSearchPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlaylistContentNotifier>();
    final results = _query.trim().isEmpty
        ? const <Song>[]
        : notifier.filteredSongs;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        children: [
          TextField(
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索歌曲或歌手',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() => _query = value);
              notifier.search(value);
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: !notifier.allSongsLoaded
                ? const Center(child: CircularProgressIndicator())
                : _query.trim().isEmpty
                ? const Center(child: Text('输入歌曲名、歌手名或拼音开始搜索'))
                : results.isEmpty
                ? const Center(child: Text('未找到匹配的歌曲'))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final song = results[index];
                      return SongTileWidget(
                        key: ValueKey('mobile-search-${song.filePath}'),
                        song: song,
                        index: index,
                        contextPlaylist: notifier.allSongsVirtualPlaylist,
                        enableContextMenu: false,
                        onTap: () =>
                            notifier.playFromDynamicList(results, index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
