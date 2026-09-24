import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import '../page/playlist/playlist_content_notifier.dart';
import 'volume_control_state.dart';
import '../page/song_detail_page.dart';
import 'balance_rate_control.dart';
import 'play_pause_button.dart';
import 'play_mode_button.dart';
import '../page/setting/settings_provider.dart';

const String mobileNowPlayingHeroTag = 'mobile-now-playing-page';
const String mobileListeningRoomHeroTag = 'mobile-listening-room-now-playing';

// 格式化时间函数
String _formatDuration(Duration duration) {
  if (duration == Duration.zero) return '00:00';
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final minutes = twoDigits(duration.inMinutes.remainder(60));
  final seconds = twoDigits(duration.inSeconds.remainder(60));
  return "$minutes:$seconds";
}

class Playbar extends StatefulWidget {
  final bool disableTap;
  final VoidCallback? onOpenNowPlaying;
  final Object? albumArtHeroTag;

  const Playbar({
    super.key,
    this.disableTap = false, // 默认不禁用点击
    this.onOpenNowPlaying,
    this.albumArtHeroTag,
  });

  @override
  State<Playbar> createState() => _PlaybarState();
}

class _PlaybarState extends State<Playbar> {
  double _currentSliderValue = 0.0;
  bool _isDraggingSlider = false; // 判断用户是否正在拖动滑块
  int _dragSessionId = 0; // 用于追踪拖动会话，避免在连续拖动时提早结束拖动状态

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _openNowPlaying(BuildContext context) {
    if (widget.disableTap) return;
    if (widget.onOpenNowPlaying != null) {
      widget.onOpenNowPlaying!();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SongDetailPage()));
  }

  Widget _buildCompactPlaybar({
    required BuildContext context,
    required PlaylistContentNotifier playlistNotifier,
    required Player player,
    required ColorScheme colorScheme,
    required Color onBarColor,
    required Color accentColor,
  }) {
    final currentSong = playlistNotifier.currentSong;
    final showAlbumName = context.watch<SettingsProvider>().showAlbumName;
    final albumCover = Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: !widget.disableTap ? () => _openNowPlaying(context) : null,
        child: SizedBox(
          width: 42,
          height: 42,
          child:
              currentSong?.albumArt != null && currentSong!.albumArt!.isNotEmpty
              ? Image.memory(
                  currentSong.albumArt!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.music_note,
                    color: onBarColor.withValues(alpha: 0.65),
                  ),
                )
              : Icon(
                  Icons.music_note,
                  color: onBarColor.withValues(alpha: 0.65),
                ),
        ),
      ),
    );

    return Container(
      height: 72,
      color: colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Column(
        children: [
          SizedBox(
            height: 20,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: accentColor,
                inactiveTrackColor: onBarColor.withValues(alpha: 0.35),
                thumbColor: accentColor,
                showValueIndicator: ShowValueIndicator.onDrag,
              ),
              child: StreamBuilder<Duration?>(
                stream: player.stream.position.throttleTime(
                  const Duration(milliseconds: 200),
                ),
                initialData: player.state.position,
                builder: (context, snapshot) {
                  final currentPosition = snapshot.data ?? Duration.zero;
                  final totalDuration = player.state.duration;
                  final sliderValue = _isDraggingSlider
                      ? _currentSliderValue
                      : totalDuration.inMilliseconds == 0
                      ? 0.0
                      : currentPosition.inMilliseconds /
                            totalDuration.inMilliseconds;

                  return Slider(
                    value: sliderValue.clamp(0.0, 1.0),
                    min: 0,
                    max: 1,
                    label: _isDraggingSlider
                        ? _formatDuration(
                            Duration(
                              milliseconds:
                                  (totalDuration.inMilliseconds * sliderValue)
                                      .round(),
                            ),
                          )
                        : null,
                    onChanged: (value) {
                      setState(() {
                        _isDraggingSlider = true;
                        _currentSliderValue = value;
                      });
                    },
                    onChangeStart: (_) {
                      _dragSessionId++;
                      _isDraggingSlider = true;
                    },
                    onChangeEnd: (value) async {
                      final currentSessionId = _dragSessionId;
                      final seekPosition = Duration(
                        milliseconds: (totalDuration.inMilliseconds * value)
                            .round(),
                      );
                      player.seek(seekPosition);
                      await Future.delayed(const Duration(milliseconds: 200));
                      if (mounted && _dragSessionId == currentSessionId) {
                        setState(() {
                          _isDraggingSlider = false;
                          _currentSliderValue =
                              totalDuration.inMilliseconds == 0
                              ? 0
                              : seekPosition.inMilliseconds /
                                    totalDuration.inMilliseconds;
                        });
                      }
                    },
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                if (widget.albumArtHeroTag != null)
                  Hero(
                    tag: widget.albumArtHeroTag!,
                    transitionOnUserGestures: true,
                    createRectTween: (begin, end) =>
                        MaterialRectCenterArcTween(begin: begin, end: end),
                    child: albumCover,
                  )
                else
                  albumCover,
                const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: currentSong != null && !widget.disableTap
                        ? () => _openNowPlaying(context)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentSong?.title ?? '未知歌曲',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: onBarColor.withValues(alpha: 0.9),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            currentSong == null
                                ? '未知歌手'
                                : showAlbumName
                                ? '${currentSong.artist} - ${currentSong.album}'
                                : currentSong.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: onBarColor.withValues(alpha: 0.65),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.skip_previous, color: onBarColor, size: 25),
                  onPressed: playlistNotifier.playPrevious,
                ),
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  initialData: playlistNotifier.isPlaying,
                  builder: (context, snapshot) {
                    final isPlaying = snapshot.data ?? false;
                    return IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 42,
                        height: 44,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        color: accentColor,
                        size: 34,
                      ),
                      onPressed: isPlaying
                          ? playlistNotifier.pause
                          : playlistNotifier.play,
                    );
                  },
                ),
                IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.skip_next, color: onBarColor, size: 25),
                  onPressed: playlistNotifier.playNext,
                ),
                IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: '播放列表',
                  icon: Icon(
                    Icons.queue_music,
                    color: onBarColor.withValues(alpha: 0.8),
                    size: 23,
                  ),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    final Color onBarColor = colorScheme.onSurface;
    final Color accentColor = colorScheme.primary;

    // 获取屏幕宽度
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 700;

    // 顶级 Consumer，确保 Playbar 整体能响应 PlaylistContentNotifier 的变化
    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        final Player player = playlistNotifier.mediaPlayer;

        if (isNarrowScreen) {
          return _buildCompactPlaybar(
            context: context,
            playlistNotifier: playlistNotifier,
            player: player,
            colorScheme: colorScheme,
            onBarColor: onBarColor,
            accentColor: accentColor,
          );
        }

        return Container(
          height: 70,
          color: colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // 左侧区
              Expanded(
                flex: 3,
                child: Consumer<PlaylistContentNotifier>(
                  builder: (context, playlistNotifier, child) {
                    final currentSong = playlistNotifier.currentSong;

                    return Row(
                      children: <Widget>[
                        // 专辑封面点击跳转歌曲详情页
                        FilledButton(
                          onPressed: (currentSong != null && !widget.disableTap)
                              ? () {
                                  // 如果有歌曲在播放且点击未被禁用，则执行跳转
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const SongDetailPage(),
                                    ),
                                  );
                                }
                              : null,
                          style: ButtonStyle(
                            fixedSize: WidgetStateProperty.all(
                              const Size(50, 50),
                            ),
                            backgroundColor: WidgetStateProperty.all(
                              colorScheme.surfaceContainerHighest,
                            ),
                            minimumSize: WidgetStateProperty.all(
                              const Size(50, 50),
                            ),
                            padding: WidgetStateProperty.all(
                              EdgeInsets.zero,
                            ), // 去除内边距
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            elevation: WidgetStateProperty.all(4),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child:
                                (currentSong?.albumArt != null &&
                                    currentSong!.albumArt!.isNotEmpty)
                                ? Image.memory(
                                    currentSong.albumArt!,
                                    fit: BoxFit.cover,
                                    width: 50,
                                    height: 50,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.music_note,
                                        color: onBarColor.withValues(
                                          alpha: 0.7,
                                        ),
                                        size: 30,
                                      );
                                    },
                                  )
                                : Icon(
                                    Icons.music_note,
                                    color: onBarColor.withValues(alpha: 0.7),
                                    size: 30,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 歌曲标题和艺术家
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                currentSong?.title ?? '未知歌曲',
                                style: TextStyle(
                                  color: onBarColor.withValues(alpha: 0.9),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              Text(
                                currentSong != null
                                    ? context
                                              .watch<SettingsProvider>()
                                              .showAlbumName
                                          ? '${currentSong.artist} - ${currentSong.album}'
                                          : currentSong.artist
                                    : '未知歌手',
                                style: TextStyle(
                                  color: onBarColor.withValues(alpha: 0.7),
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // 中间区
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    // 播放进度条
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.0,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6.0,
                        ),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: accentColor,
                        inactiveTrackColor: onBarColor.withValues(alpha: 0.7),
                        thumbColor: accentColor,
                        showValueIndicator: ShowValueIndicator.onDrag,
                      ),
                      child: StreamBuilder<Duration?>(
                        stream: player.stream.position.throttleTime(
                          const Duration(milliseconds: 200),
                        ),
                        initialData: player.state.position,
                        builder: (context, snapshot) {
                          final currentPosition =
                              snapshot.data ?? Duration.zero;
                          final totalDuration = player.state.duration;
                          double sliderValue = 0.0;

                          if (_isDraggingSlider) {
                            sliderValue = _currentSliderValue;
                          } else {
                            sliderValue = totalDuration.inMilliseconds == 0
                                ? 0.0
                                : currentPosition.inMilliseconds /
                                      totalDuration.inMilliseconds;
                          }

                          return Slider(
                            value: sliderValue.clamp(0.0, 1.0),
                            min: 0.0,
                            max: 1.0,
                            label: _isDraggingSlider
                                ? _formatDuration(
                                    Duration(
                                      milliseconds:
                                          (player
                                                      .state
                                                      .duration
                                                      .inMilliseconds *
                                                  sliderValue)
                                              .round(),
                                    ),
                                  )
                                : null,
                            onChanged: (double newValue) {
                              // 用户拖动时，只更新内部状态
                              setState(() {
                                _isDraggingSlider = true;
                                _currentSliderValue = newValue;
                              });
                            },
                            onChangeStart: (double startValue) {
                              _dragSessionId++;
                              _isDraggingSlider = true; // 开始拖动
                            },
                            onChangeEnd: (double endValue) async {
                              final currentSessionId = _dragSessionId;

                              // 获取当前总时长，用于计算seek位置
                              final totalDuration = player.state.duration;

                              final seekPosition = Duration(
                                milliseconds:
                                    (totalDuration.inMilliseconds * endValue)
                                        .round(),
                              );
                              player.seek(seekPosition); // 拖动结束后才实际 seek

                              // 等待一小段时间，让播放器状态流更新，避免进度条闪烁
                              await Future.delayed(
                                const Duration(milliseconds: 200),
                              );

                              // 拖动结束后，立即更新滑块到最终位置，即使定时器还未触发
                              if (mounted &&
                                  _dragSessionId == currentSessionId) {
                                setState(() {
                                  _isDraggingSlider = false; // 结束拖动
                                  _currentSliderValue =
                                      totalDuration.inMilliseconds == 0
                                      ? 0.0
                                      : seekPosition.inMilliseconds /
                                            totalDuration.inMilliseconds;
                                });
                              }
                            },
                          );
                        },
                      ),
                    ),
                    // 播放控制按钮 (上一首、播放/暂停、下一首)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        // 上一首按钮
                        IconButton(
                          icon: Icon(
                            Icons.skip_previous,
                            color: onBarColor,
                            size: 28,
                          ),
                          onPressed: () => playlistNotifier.playPrevious(),
                        ),
                        // 播放/暂停按钮 (根据播放器状态动态更新)
                        StreamBuilder<bool>(
                          stream: player.stream.playing,
                          initialData: playlistNotifier.isPlaying,
                          builder: (context, snapshot) {
                            final isPlaying = snapshot.data ?? false;
                            return PlayPauseButton(
                              isPlaying: isPlaying,
                              color: accentColor,
                              onPressed: isPlaying
                                  ? playlistNotifier.pause
                                  : playlistNotifier.play,
                            );
                          },
                        ),
                        // 下一首按钮
                        IconButton(
                          icon: Icon(
                            Icons.skip_next,
                            color: onBarColor,
                            size: 28,
                          ),
                          onPressed: () => playlistNotifier.playNext(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 右侧区
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    // 播放时间显示 (当前时间 / 总时长)
                    StreamBuilder<Duration?>(
                      stream: player.stream.position.throttleTime(
                        const Duration(milliseconds: 200),
                      ), // 监听当前位置
                      initialData: playlistNotifier
                          .currentPosition, // 使用 Notifier 中的同步数据
                      builder: (context, positionSnapshot) {
                        final currentPosition =
                            positionSnapshot.data ?? Duration.zero;
                        return StreamBuilder<Duration?>(
                          stream: player.stream.duration, // 监听总时长
                          initialData: playlistNotifier
                              .totalDuration, // 使用 Notifier 中的同步数据
                          builder: (context, totalDurationSnapshot) {
                            final totalDuration =
                                totalDurationSnapshot.data ?? Duration.zero;
                            return RepaintBoundary(
                              child: Text(
                                '${_formatDuration(currentPosition)} / ${_formatDuration(totalDuration)}',
                                style: TextStyle(
                                  color: onBarColor.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    // 随机播放/列表循环按钮 (根据 playMode 动态更新)
                    if (!isNarrowScreen) ...[
                      // 播放模式
                      Consumer<PlaylistContentNotifier>(
                        builder: (context, notifier, _) {
                          return PlayModeButton(
                            playMode: notifier.playMode,
                            color: onBarColor.withValues(alpha: 0.7),
                            activeColor: accentColor,
                            onPressed: () {
                              notifier.togglePlayMode();
                            },
                          );
                        },
                      ),
                      // 音量控制
                      VolumeControl(player: player, iconColor: onBarColor),
                      // // 平衡速率控制
                      BalanceRateControl(player: player, iconColor: onBarColor),
                      // 播放列表
                      IconButton(
                        style: const ButtonStyle(
                          mouseCursor: WidgetStatePropertyAll(
                            SystemMouseCursors.click,
                          ),
                        ),
                        icon: const Icon(Icons.lyrics_outlined),
                        iconSize: 23,
                        tooltip: '播放列表',
                        padding: const EdgeInsets.only(top: 1.5),
                        onPressed: () {
                          // 打开右侧抽屉
                          Scaffold.of(context).openEndDrawer();
                        },
                      ),
                    ],

                    // // 桌面歌词按钮
                    // IconButton(
                    //   icon: Icon(
                    //     Icons.queue_music,
                    //     color: onBarColor.withValues(alpha: 0.7),
                    //     size: 24,
                    //   ),
                    //   onPressed: () {
                    //     // TODO: 桌面歌词功能
                    //     // 使用desktop_multi_window或等待官方更新
                    //   },
                    // ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
