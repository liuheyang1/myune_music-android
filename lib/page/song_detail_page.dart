// 音频可视化:https://pub.dev/packages/sonix

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mesh_gradient/mesh_gradient.dart';
import 'package:colorgram/colorgram.dart';

import 'playlist/playlist_content_notifier.dart';
import '../widgets/song_detail_page/playbar.dart';
import '../widgets/song_detail_page/app_window_title_bar.dart';
import './setting/settings_provider.dart';
import '../widgets/playing_queue_drawer.dart';
import '../widgets/lyrics_settings_drawer.dart';
import '../widgets/immersive_scene_background.dart';
import 'playlist/playlist_models.dart';

// 公共模糊背景组件
class BackgroundBlurWidget extends StatefulWidget {
  final Widget child;
  const BackgroundBlurWidget({super.key, required this.child});

  @override
  State<BackgroundBlurWidget> createState() => _BackgroundBlurWidgetState();
}

class _BackgroundBlurWidgetState extends State<BackgroundBlurWidget>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  List<Color>? _extractedColors;
  String? _lastSongFilePath;
  bool _isProcessingColor = false;

  // 初始网格位置
  static const List<Offset> _gridPositions = [
    Offset(0.15, 0.2),
    Offset(0.85, 0.15),
    Offset(0.2, 0.85),
    Offset(0.8, 0.8),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _checkAndUpdateColors(Song? song, bool isDarkTheme) {
    if (song == null || song.albumArt == null) {
      if (_extractedColors != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _extractedColors = null);
        });
      }
      return;
    }

    if (song.filePath == _lastSongFilePath || _isProcessingColor) return;

    _lastSongFilePath = song.filePath;
    _isProcessingColor = true;

    _extractColorsAsync(song, isDarkTheme);
  }

  Future<void> _extractColorsAsync(Song song, bool isDarkTheme) async {
    try {
      final ImageProvider imageProvider = MemoryImage(song.albumArt!);
      final List<CgColor> cgColors = await extractColor(imageProvider, 6);

      if (!mounted || song.filePath != _lastSongFilePath) return;

      final List<Color> adjustedColors = cgColors.map((cg) {
        final rawColor = Color.fromARGB(255, cg.r, cg.g, cg.b);
        final hsl = HSLColor.fromColor(rawColor);

        double newLightness;
        double newSaturation;

        if (isDarkTheme) {
          newLightness = hsl.lightness.clamp(0.08, 0.18);
          newSaturation = hsl.saturation.clamp(0.18, 0.35);
        } else {
          newLightness = hsl.lightness.clamp(0.35, 0.55);
          newSaturation = hsl.saturation.clamp(0.18, 0.38);
        }

        return hsl
            .withLightness(newLightness)
            .withSaturation(newSaturation)
            .toColor();
      }).toList();

      while (adjustedColors.length < 4) {
        adjustedColors.add(
          adjustedColors.isNotEmpty ? adjustedColors.first : Colors.blueGrey,
        );
      }

      if (mounted) {
        setState(() {
          _extractedColors = adjustedColors.sublist(0, 4);
        });
      }
    } catch (e) {
      //
    } finally {
      _isProcessingColor = false;
    }
  }

  List<MeshGradientPoint> _getMeshPoints(bool isDarkTheme) {
    final List<Color> baseColors =
        _extractedColors ??
        (isDarkTheme
            ? const [
                Color(0xFF0B0B0F),
                Color(0xFF08090D),
                Color(0xFF0A0B10),
                Color(0xFF0D0A12),
              ]
            : const [
                Color(0xFFD6D0D2),
                Color(0xFFD0D5D8),
                Color(0xFFD5D8DC),
                Color(0xFFD8D1D6),
              ]);

    return List.generate(_gridPositions.length, (i) {
      return MeshGradientPoint(
        position: _gridPositions[i],
        // 浅色模式下不稀释颜色
        color: baseColors[i].withValues(alpha: isDarkTheme ? 0.28 : 1.0),
      );
    });
  }

  void _manageAnimation(bool shouldAnimate) {
    if (shouldAnimate) {
      if (!_animationController.isAnimating) {
        _animationController.repeat(reverse: true); // 重复播放，反向播放
      }
    } else {
      if (_animationController.isAnimating) {
        _animationController.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final useBlurBackground = settings.useBlurBackground;
    final enableDynamicBackground = settings.enableDynamicBackground;

    // 动画开关逻辑，通过延迟到帧后来避免 build 期间的副作用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _manageAnimation(enableDynamicBackground && useBlurBackground);
      }
    });

    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, child) {
        final currentSong = playlistNotifier.currentSong;

        _checkAndUpdateColors(currentSong, isDarkTheme);
        // 当没有封面图或用户未启用模糊背景时，使用纯色背景
        if (currentSong?.albumArt == null || !useBlurBackground) {
          return Container(
            color: Theme.of(context).colorScheme.surface,
            child: child,
          );
        }

        if (enableDynamicBackground) {
          final basePoints = _getMeshPoints(isDarkTheme);

          return Stack(
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _animation,
                builder: (context, _) {
                  final List<MeshGradientPoint> animatedPoints = [];
                  const double amplitude = 0.35;
                  final double time = _animation.value * 2 * math.pi;

                  for (int i = 0; i < basePoints.length; i++) {
                    final point = basePoints[i];
                    double offsetX = 0.0;
                    double offsetY = 0.0;

                    if (i == 0) {
                      offsetX = amplitude * math.sin(time);
                      offsetY = amplitude * math.cos(time * 1.2);
                    } else if (i == 1) {
                      offsetX = amplitude * math.cos(time * 0.9);
                      offsetY = amplitude * math.sin(time * 1.1);
                    } else if (i == 2) {
                      offsetX = amplitude * math.sin(time * 1.3);
                      offsetY = amplitude * math.sin(time * 0.8);
                    } else {
                      offsetX = amplitude * math.cos(time * 1.1);
                      offsetY = amplitude * math.cos(time * 1.4);
                    }

                    animatedPoints.add(
                      MeshGradientPoint(
                        position: Offset(
                          (point.position.dx + offsetX).clamp(0.0, 1.0),
                          (point.position.dy + offsetY).clamp(0.0, 1.0),
                        ),
                        color: point.color,
                      ),
                    );
                  }

                  return MeshGradient(
                    points: animatedPoints,
                    options: MeshGradientOptions(
                      blend: 4.0,
                      noiseIntensity: 0.1,
                    ),
                  );
                },
              ),
              Container(
                color: Theme.of(context).colorScheme.surface.withValues(
                  alpha: isDarkTheme ? 0.4 : 0.6,
                ),
              ),
              if (child != null) child,
            ],
          );
        }

        // 静态高斯模糊背景部分
        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 40,
                sigmaY: 40,
                tileMode: TileMode.decal,
              ),
              child: Image.memory(
                currentSong!.albumArt!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Container(color: Theme.of(context).colorScheme.surface),
              ),
            ),
            IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.8),
                      Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
            ),
            if (child != null) child,
          ],
        );
      },
      child: widget.child,
    );
  }
}

class SongDetailPage extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onNavigationPressed;
  final Object? heroTag;
  final bool startInFocusMode;

  const SongDetailPage({
    super.key,
    this.embedded = false,
    this.onNavigationPressed,
    this.heroTag,
    this.startInFocusMode = false,
  });

  @override
  State<SongDetailPage> createState() => _SongDetailPageState();
}

class _SongDetailPageState extends State<SongDetailPage>
    with WidgetsBindingObserver {
  bool _isHidden = false;
  Timer? _hideTimer;
  Timer? _playbarHideTimer;
  bool _isPlaybarHidden = false;
  bool _lastSettingValue = false;
  bool? _lastImmersiveLandscape;
  late bool _focusMode;

  static const _playbarHideDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _focusMode = widget.startInFocusMode;
    WidgetsBinding.instance.addObserver(this);
    _restartPlaybarHideTimer();
    if (Platform.isAndroid || Platform.isIOS) {
      unawaited(
        SystemChrome.setPreferredOrientations(
          _focusMode
              ? [
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]
              : [DeviceOrientation.portraitUp],
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSystemUi());
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSystemUi());
  }

  Future<void> _syncSystemUi() async {
    if (!mounted || !Platform.isAndroid) return;
    final immersiveLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (_lastImmersiveLandscape == immersiveLandscape) return;
    _lastImmersiveLandscape = immersiveLandscape;

    final brightness = Theme.of(context).brightness;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: brightness,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    await SystemChrome.setEnabledSystemUIMode(
      immersiveLandscape
          ? SystemUiMode.immersiveSticky
          : SystemUiMode.edgeToEdge,
    );
  }

  Future<void> _enterFocusMode() async {
    if (!mounted || !(Platform.isAndroid || Platform.isIOS)) return;
    setState(() {
      _focusMode = true;
      _isPlaybarHidden = false;
    });
    _restartPlaybarHideTimer();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _exitFocusMode() async {
    if (!mounted || !(Platform.isAndroid || Platform.isIOS)) return;
    setState(() => _focusMode = false);
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  void _startTimer() {
    _cancelTimer();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isHidden = true;
        });
      }
    });
  }

  void _cancelTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _restartPlaybarHideTimer() {
    _playbarHideTimer?.cancel();
    _playbarHideTimer = Timer(_playbarHideDelay, () {
      if (mounted) setState(() => _isPlaybarHidden = true);
    });
  }

  void _handlePlaybarInteraction() {
    if (_isPlaybarHidden) {
      setState(() => _isPlaybarHidden = false);
    }
    _restartPlaybarHideTimer();
  }

  void _handleInteraction(bool autoHideEnabled) {
    _handleUserInteraction(autoHideEnabled);
    _handlePlaybarInteraction();
  }

  void _handleUserInteraction(bool autoHideEnabled) {
    if (!autoHideEnabled) return;
    _cancelTimer();
    if (_isHidden) {
      setState(() {
        _isHidden = false;
      });
    }
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelTimer();
    _playbarHideTimer?.cancel();
    if (Platform.isAndroid) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    if (Platform.isAndroid || Platform.isIOS) {
      unawaited(
        SystemChrome.setPreferredOrientations(DeviceOrientation.values),
      );
    }
    super.dispose();
  }

  Widget _buildPortraitPlayer(double scale) {
    return Consumer<PlaylistContentNotifier>(
      builder: (context, playlistNotifier, _) {
        final currentSong = playlistNotifier.currentSong;
        final currentLyrics = playlistNotifier.currentLyrics;
        final colorScheme = Theme.of(context).colorScheme;

        return LayoutBuilder(
          builder: (context, constraints) {
            final artworkSize = math
                .min(constraints.maxWidth - 48, constraints.maxHeight * 0.52)
                .clamp(150.0, 360.0);
            final artwork = Container(
              width: artworkSize,
              height: artworkSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20 * scale),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 28 * scale,
                    offset: Offset(0, 12 * scale),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child:
                  currentSong?.albumArt != null &&
                      currentSong!.albumArt!.isNotEmpty
                  ? Image.memory(
                      currentSong.albumArt!,
                      key: ValueKey(currentSong.filePath),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) =>
                          _ArtworkPlaceholder(colorScheme: colorScheme),
                    )
                  : _ArtworkPlaceholder(colorScheme: colorScheme),
            );

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 24 * scale),
              child: Column(
                children: [
                  const Spacer(),
                  if (widget.heroTag != null)
                    Hero(
                      tag: widget.heroTag!,
                      transitionOnUserGestures: true,
                      createRectTween: (begin, end) =>
                          MaterialRectCenterArcTween(begin: begin, end: end),
                      child: Material(
                        type: MaterialType.transparency,
                        child: artwork,
                      ),
                    )
                  else
                    artwork,
                  SizedBox(height: 24 * scale),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentSong?.title ?? '暂无播放歌曲',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 22 * scale,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4 * scale),
                            Text(
                              currentSong?.artist ?? '请先从音乐库选择歌曲',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15 * scale,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 12 * scale),
                      IconButton.filledTonal(
                        onPressed: _enterFocusMode,
                        tooltip: '专注模式',
                        icon: const Icon(Icons.music_note_rounded),
                      ),
                    ],
                  ),
                  SizedBox(height: 18 * scale),
                  SizedBox(
                    height: 52 * scale,
                    child: Center(
                      child: currentLyrics.isEmpty
                          ? Text(
                              '暂无歌词',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 15 * scale,
                              ),
                            )
                          : StreamBuilder<int>(
                              stream: playlistNotifier.lyricLineIndexStream,
                              initialData:
                                  playlistNotifier.currentLyricLineIndex,
                              builder: (context, snapshot) {
                                final index =
                                    snapshot.data ??
                                    playlistNotifier.currentLyricLineIndex;
                                var text = '♪';
                                if (index >= 0 &&
                                    index < currentLyrics.length &&
                                    currentLyrics[index].texts.isNotEmpty) {
                                  final candidate = currentLyrics[index]
                                      .texts
                                      .first
                                      .trim();
                                  if (candidate.isNotEmpty) text = candidate;
                                }
                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 240),
                                  child: Text(
                                    text,
                                    key: ValueKey('$index:$text'),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16 * scale,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final autoHideEnabled = settings.autoHidePlayPageComponents;

    // 监听设置变化
    if (autoHideEnabled != _lastSettingValue) {
      _lastSettingValue = autoHideEnabled;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (autoHideEnabled) {
          _startTimer();
        } else {
          _cancelTimer();
          if (mounted && _isHidden) {
            setState(() {
              _isHidden = false;
            });
          }
        }
      });
    }

    // 获取窗口宽高比
    final size = MediaQuery.of(context).size;
    final aspectRatio = size.aspectRatio;
    final isPortrait = aspectRatio <= 1.0; // 竖屏判断
    final isMobilePortrait =
        isPortrait && (Platform.isAndroid || Platform.isIOS);
    final hideChrome = !isPortrait && _isHidden;

    // 计算窗口分辨率缩放系数
    final double width = size.width > 0 ? size.width : 1150.0;
    final double height = size.height > 0 ? size.height : 620.0;
    final double scale = (math.sqrt(
      (width * height) / (1150.0 * 620.0),
    )).clamp(0.5, 2.0);
    final double portraitScale = (width / 430.0).clamp(0.88, 1.15);

    return PopScope(
      canPop: !_focusMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _focusMode) unawaited(_exitFocusMode());
      },
      child: Listener(
        onPointerDown: (_) => _handleInteraction(autoHideEnabled),
        onPointerMove: (_) => _handleInteraction(autoHideEnabled),
        onPointerHover: (_) => _handleInteraction(autoHideEnabled),
        onPointerSignal: (_) => _handleInteraction(autoHideEnabled),
        child: MouseRegion(
          cursor: hideChrome ? SystemMouseCursors.none : MouseCursor.defer,
          onHover: (_) => _handleInteraction(autoHideEnabled),
          child: Scaffold(
            endDrawer: const PlayingQueueDrawer(),
            body: _PlaybackBackground(
              useAlbumBlur: isMobilePortrait,
              child: SafeArea(
                top: isPortrait,
                bottom: isPortrait,
                left: isPortrait,
                right: isPortrait,
                child: Column(
                  children: [
                    // 标题栏
                    if (!_focusMode || isPortrait)
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: hideChrome ? 0.0 : 1.0,
                        child: IgnorePointer(
                          ignoring: hideChrome,
                          child: Builder(
                            builder: (BuildContext context) {
                              return AppWindowTitleBar(
                                showBackButton: !widget.embedded,
                                showSettingsButton:
                                    !(Platform.isAndroid || Platform.isIOS),
                                onNavigationPressed: widget.onNavigationPressed,
                                onSettingsPressed: () {
                                  Scaffold.of(context).openDrawer();
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    // 主内容区域
                    Expanded(
                      child: isPortrait
                          ? // 竖屏：标准手机播放器，封面、歌曲信息、歌词与控制
                            Column(
                              children: [
                                Expanded(
                                  child: _buildPortraitPlayer(portraitScale),
                                ),
                                const PortraitPlaybar(),
                              ],
                            )
                          : // 横屏：沉浸式背景、中央歌词和底部播放栏
                            Stack(
                              fit: StackFit.expand,
                              children: [
                                Consumer<PlaylistContentNotifier>(
                                  builder: (context, playlistNotifier, _) {
                                    final currentLyrics =
                                        playlistNotifier.currentLyrics;
                                    final currentSong =
                                        playlistNotifier.currentSong;

                                    const infoColor = Color(0xFF23496B);
                                    final Widget lyricsContent;
                                    if (currentLyrics.isEmpty) {
                                      lyricsContent = Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            currentSong?.title ?? '未知歌曲',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: infoColor,
                                              fontFamily: 'KaiTi',
                                              fontSize: 30 * scale,
                                              fontWeight: FontWeight.w500,
                                              fontStyle: FontStyle.italic,
                                              letterSpacing: 0.8 * scale,
                                            ),
                                          ),
                                          SizedBox(height: 8 * scale),
                                          Text(
                                            currentSong?.artist ?? '未知歌手/乐队',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: infoColor.withValues(
                                                alpha: 0.86,
                                              ),
                                              fontFamily: 'KaiTi',
                                              fontSize: 18 * scale,
                                              fontWeight: FontWeight.w400,
                                              fontStyle: FontStyle.italic,
                                              letterSpacing: 0.4 * scale,
                                            ),
                                          ),
                                        ],
                                      );
                                    } else {
                                      lyricsContent = StreamBuilder<int>(
                                        stream: playlistNotifier
                                            .lyricLineIndexStream,
                                        initialData: playlistNotifier
                                            .currentLyricLineIndex,
                                        builder: (context, snapshot) {
                                          final currentIndex =
                                              snapshot.data ??
                                              playlistNotifier
                                                  .currentLyricLineIndex;
                                          String? lyricText;
                                          if (currentIndex >= 0 &&
                                              currentIndex <
                                                  currentLyrics.length) {
                                            final currentLine =
                                                currentLyrics[currentIndex];
                                            if (!currentLine.isInterlude &&
                                                currentLine.texts.isNotEmpty) {
                                              final text = currentLine
                                                  .texts
                                                  .first
                                                  .trim();
                                              if (text.isNotEmpty) {
                                                lyricText = text;
                                              }
                                            }
                                          }

                                          if (lyricText == null) {
                                            return const SizedBox.shrink();
                                          }

                                          return AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 260,
                                            ),
                                            transitionBuilder:
                                                (child, animation) {
                                                  return FadeTransition(
                                                    opacity: animation,
                                                    child: child,
                                                  );
                                                },
                                            child: Text(
                                              lyricText,
                                              key: ValueKey(
                                                '$currentIndex:$lyricText',
                                              ),
                                              textAlign: TextAlign.center,
                                              softWrap: true,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: infoColor,
                                                fontFamily: 'KaiTi',
                                                fontSize: 27 * scale,
                                                fontWeight: FontWeight.w500,
                                                fontStyle: FontStyle.italic,
                                                letterSpacing: 0.8 * scale,
                                                height: 1.25,
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    }

                                    return Positioned.fill(
                                      child: Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          80 * scale,
                                          18 * scale,
                                          80 * scale,
                                          112 * scale,
                                        ),
                                        child: Center(
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: math.min(
                                                650 * scale,
                                                size.width * 0.64,
                                              ),
                                            ),
                                            child: Align(
                                              alignment: const Alignment(
                                                0,
                                                -0.38,
                                              ),
                                              child: lyricsContent,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 12 * scale,
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 600,
                                      ),
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: AnimatedSlide(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          offset: _isPlaybarHidden
                                              ? const Offset(0, 1.2)
                                              : Offset.zero,
                                          child: AnimatedOpacity(
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            opacity:
                                                _isHidden || _isPlaybarHidden
                                                ? 0.0
                                                : 1.0,
                                            child: IgnorePointer(
                                              ignoring:
                                                  _isHidden || _isPlaybarHidden,
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.34),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        18 * scale,
                                                      ),
                                                ),
                                                child: Padding(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 14 * scale,
                                                    vertical: 6 * scale,
                                                  ),
                                                  child: const Playbar(),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
            drawer: const LyricsSettingsDrawer(),
          ),
        ),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  final ColorScheme colorScheme;

  const _ArtworkPlaceholder({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 72,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}

class _PlaybackBackground extends StatelessWidget {
  final bool useAlbumBlur;
  final Widget child;

  const _PlaybackBackground({required this.useAlbumBlur, required this.child});

  @override
  Widget build(BuildContext context) {
    return useAlbumBlur
        ? BackgroundBlurWidget(child: child)
        : ImmersiveSceneBackground(child: child);
  }
}
