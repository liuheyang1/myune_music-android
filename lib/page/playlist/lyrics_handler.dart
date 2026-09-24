import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

import 'playlist_models.dart';
import '../setting/settings_provider.dart';
import '../../src/rust/api/audio_info.dart';
import '../../services/notification_service.dart';

class LyricsHandler {
  final SettingsProvider _settingsProvider;
  final NotificationService _notificationService;
  final VoidCallback _notifyListeners;
  final Song? Function() _getCurrentSong;

  List<LyricLine> _currentLyrics = [];
  int _currentLyricLineIndex = -1;
  final StreamController<int> _lyricLineIndexController =
      StreamController<int>.broadcast();

  LyricsHandler({
    required SettingsProvider settingsProvider,
    required NotificationService notificationService,
    required VoidCallback notifyListeners,
    required Song? Function() getCurrentSong,
  }) : _settingsProvider = settingsProvider,
       _notificationService = notificationService,
       _notifyListeners = notifyListeners,
       _getCurrentSong = getCurrentSong;

  List<LyricLine> get currentLyrics => _currentLyrics;
  int get currentLyricLineIndex => _currentLyricLineIndex;
  Stream<int> get lyricLineIndexStream => _lyricLineIndexController.stream;

  List<String> _buildOnlineSearchKeywords(String songTitle) {
    final title = songTitle.trim();
    final rawArtist = _getCurrentSong()?.artist.trim() ?? '';
    final artist = (rawArtist == '未知歌手' || rawArtist == '未知歌手 (解析失败)')
        ? ''
        : rawArtist;

    final keywords = <String>[title];
    if (artist.isNotEmpty) {
      keywords.add('$title $artist');
      keywords.add('$artist - $title');
    }
    return keywords.toSet().toList();
  }

  Future<void> _loadFromOnlineSource(String source, String songTitle) async {
    for (final keyword in _buildOnlineSearchKeywords(songTitle)) {
      switch (source) {
        case 'qq':
          await _loadQQLyrics(songTitle, queryOverride: keyword);
        case 'netease':
          await _loadOnlineLyrics(songTitle, queryOverride: keyword);
        case 'kugou':
          await _loadKugouLyrics(songTitle, queryOverride: keyword);
      }
      if (_currentLyrics.isNotEmpty) return;
    }
  }

  void clearLyrics() {
    _currentLyrics = [];
    _currentLyricLineIndex = -1;
    _lyricLineIndexController.add(-1);
    _notifyListeners();
  }

  void dispose() {
    _lyricLineIndexController.close();
  }

  // 加载指定歌曲的歌词
  Future<void> loadLyricsForSong(String songFilePath) async {
    _currentLyrics = []; // 清空之前的歌词
    _currentLyricLineIndex = -1; // 重置歌词行索引
    _lyricLineIndexController.add(-1);
    _notifyListeners();

    if (_settingsProvider.preferExternalLyrics) {
      // 优先读取外置LRC歌词
      await _loadExternalLyrics(songFilePath);
      if (_currentLyrics.isNotEmpty) {
        return;
      }
      // 内嵌歌词
      await _loadEmbeddedLyrics(songFilePath);
      if (_currentLyrics.isNotEmpty) {
        return;
      }
    } else {
      // 优先读取内嵌歌词
      await _loadEmbeddedLyrics(songFilePath);
      if (_currentLyrics.isNotEmpty) {
        return;
      }
      // 外置歌词
      await _loadExternalLyrics(songFilePath);
      if (_currentLyrics.isNotEmpty) {
        return;
      }
    }

    if (_settingsProvider.enableOnlineLyrics && _getCurrentSong() != null) {
      _currentLyrics = []; // 清空歌词
      _notifyListeners();

      final sources = {
        _settingsProvider.primaryLyricSource,
        _settingsProvider.secondaryLyricSource,
        'qq',
        'netease',
        'kugou',
      };

      for (final source in sources) {
        await _loadFromOnlineSource(source, _getCurrentSong()!.title);
        if (_currentLyrics.isNotEmpty) return;
      }
    } else {
      _currentLyrics = []; // 确保在不执行网络请求时清空歌词
      _notifyListeners();
    }
  }

  Future<void> _loadExternalLyrics(String songFilePath) async {
    final songDirectory = p.dirname(songFilePath);
    final songFileNameWithoutExtension = p.basenameWithoutExtension(
      songFilePath,
    );
    final lrcFilePath = p.join(
      songDirectory,
      '$songFileNameWithoutExtension.lrc',
    );

    final lrcFile = File(lrcFilePath);

    if (await lrcFile.exists()) {
      try {
        final lines = await lrcFile.readAsLines();
        _currentLyrics = _parseLrcContent(lines);
        _notifyListeners();
        return;
      } catch (e) {
        // debugPrint('读取.lrc文件失败：$e');
      }
    }
  }

  // 加载内嵌歌词
  Future<void> _loadEmbeddedLyrics(String songFilePath) async {
    try {
      final normalizedPath = Uri.file(
        songFilePath,
      ).toFilePath(windows: Platform.isWindows);
      final file = File(normalizedPath);

      if (!await file.exists()) {
        _notificationService.error('歌曲文件不存在：${p.basename(songFilePath)}');
        _notifyListeners();
        return;
      }

      final metadata = await readAudioInfo(
        path: normalizedPath,
        options: const AudioInfoOptions(
          needCover: false,
          needLyrics: true,
          needAudioProps: false,
          needExtraTags: false,
          needTrackNumber: false,
        ),
      );

      if (metadata.lyrics != null && metadata.lyrics!.isNotEmpty) {
        final lines = metadata.lyrics!.split(RegExp(r'\r?\n'));
        _currentLyrics = _parseLrcContent(lines);
        _notifyListeners();
        return;
      }
    } catch (e) {
      // _notificationService.error('加载歌词失败：${p.basename(songFilePath)}');
      // 未能读取到歌词时不提示错误
    }
  }

  // 后台异步加载网易歌词
  Future<void> _loadOnlineLyrics(
    String songTitle, {
    String? queryOverride,
  }) async {
    try {
      // 检查 artist 是否为默认值，如果是则设置为空字符串
      final rawArtist = _getCurrentSong()?.artist ?? '';
      final artist = (rawArtist == '未知歌手' || rawArtist == '未知歌手 (解析失败)')
          ? ''
          : rawArtist;

      // 组合搜索关键词（有歌手时：歌名 + 歌手；否则只用歌名）
      final searchKeyword =
          queryOverride ??
          (artist.isEmpty
              ? songTitle.trim()
              : '${songTitle.trim()} ${artist.trim()}');

      // 对搜索关键词进行 url 编码
      final encodedSearchKeyword = Uri.encodeComponent(searchKeyword);

      // 第一步：搜索歌曲获取歌曲id
      final searchUrl =
          'https://music.163.com/api/search/get/?s=$encodedSearchKeyword&type=1&limit=1';
      final searchUri = Uri.parse(searchUrl);

      final searchResponse = await http
          .get(
            searchUri,
            headers: {
              'Referer': 'https://music.163.com',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 10));

      // 如果状态码不为200，清空并返回
      if (searchResponse.statusCode != 200) {
        _currentLyrics = [];
        _notifyListeners();
        return;
      }

      // 解析搜索结果
      final searchResult = json.decode(searchResponse.body);

      // 如果没有找到歌曲，同样清空歌词
      if (searchResult['result'] == null ||
          searchResult['result']['songs'] == null ||
          searchResult['result']['songs'].isEmpty) {
        _currentLyrics = [];
        _notifyListeners();
        return;
      }

      // 取第一首匹配歌曲的id
      final songId = searchResult['result']['songs'][0]['id'].toString();

      // 第二步：分别获取原文歌词和翻译歌词
      // 获取原文歌词
      final lrcUrl =
          'https://music.163.com/api/song/lyric?os=pc&id=$songId&lv=-1';
      final lrcUri = Uri.parse(lrcUrl);

      final lrcResponse = await http
          .get(
            lrcUri,
            headers: {
              'Referer': 'https://music.163.com',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 10));

      // 如果状态码不为200，清空并返回
      if (lrcResponse.statusCode != 200) {
        _currentLyrics = [];
        _notifyListeners();
        return;
      }

      final lrcResult = json.decode(lrcResponse.body);

      // 获取翻译歌词
      final tlyricUrl =
          'https://music.163.com/api/song/lyric?os=pc&id=$songId&tv=-1';
      final tlyricUri = Uri.parse(tlyricUrl);

      final tlyricResponse = await http
          .get(
            tlyricUri,
            headers: {
              'Referer': 'https://music.163.com',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 10));

      final tlyricResult = json.decode(tlyricResponse.body);

      // 处理原文歌词数据
      List<String> lrcLines = [];
      if (lrcResult['lrc'] != null &&
          lrcResult['lrc']['lyric'] != null &&
          lrcResult['lrc']['lyric'].toString().isNotEmpty) {
        lrcLines = lrcResult['lrc']['lyric'].toString().split('\n');
      }

      // 处理翻译歌词数据
      List<String> tlyricLines = [];
      if (tlyricResult['tlyric'] != null &&
          tlyricResult['tlyric']['lyric'] != null &&
          tlyricResult['tlyric']['lyric'].toString().isNotEmpty) {
        tlyricLines = tlyricResult['tlyric']['lyric'].toString().split('\n');
      }

      // 合并歌词
      final List<String> mergedLyrics = [];
      mergedLyrics.addAll(lrcLines);

      if (tlyricLines.isNotEmpty) {
        mergedLyrics.add(''); // 空行分隔
        mergedLyrics.addAll(tlyricLines);
      }

      // 解析歌词
      _currentLyrics = _parseLrcContent(mergedLyrics);
    } catch (e) {
      _currentLyrics = [];
    }
    _notifyListeners();
  }

  // 酷狗歌词获取方法
  Future<void> _loadKugouLyrics(
    String songTitle, {
    String? queryOverride,
  }) async {
    try {
      // 检查 artist 是否为默认值，如果是则设置为空字符串
      final rawArtist = _getCurrentSong()?.artist ?? '';
      final artist = (rawArtist == '未知歌手' || rawArtist == '未知歌手 (解析失败)')
          ? ''
          : rawArtist;

      // 组合搜索关键词（有歌手时：歌名 + 歌手；否则只用歌名）
      final searchKeyword =
          queryOverride ??
          (artist.isEmpty
              ? songTitle.trim()
              : '${songTitle.trim()} ${artist.trim()}');

      // 对搜索关键词进行 url 编码
      final encodedSearchKeyword = Uri.encodeComponent(searchKeyword);

      // 第一步：搜索歌曲获取歌曲hash
      final searchUrl =
          'http://mobilecdnbj.kugou.com/api/v3/search/song?keyword=$encodedSearchKeyword&page=1&pagesize=1';
      final searchUri = Uri.parse(searchUrl);

      final searchResponse = await http
          .get(searchUri)
          .timeout(const Duration(seconds: 10));

      // 如果状态码不为200，清空并返回
      if (searchResponse.statusCode != 200) {
        _currentLyrics = [];
        _notifyListeners();
        return;
      }

      // 解析搜索结果
      final searchResult = json.decode(searchResponse.body);

      // 如果没有找到歌曲，同样清空歌词
      if (searchResult['data'] == null ||
          searchResult['data']['info'] == null ||
          searchResult['data']['info'].isEmpty) {
        _currentLyrics = [];
        _notifyListeners();
        return;
      }

      // 取第一首匹配歌曲的hash
      final songHash = searchResult['data']['info'][0]['hash'].toString();

      // 第二步：获取歌词候选列表
      final candidatesUrl =
          'https://krcs.kugou.com/search?man=yes&hash=$songHash';
      final candidatesUri = Uri.parse(candidatesUrl);

      final candidatesResponse = await http
          .get(candidatesUri)
          .timeout(const Duration(seconds: 10));

      // 如果状态码不为200，清空并返回
      if (candidatesResponse.statusCode != 200) {
        _currentLyrics = [];
        _notifyListeners();
        return;
      }

      final candidatesResult = json.decode(candidatesResponse.body);

      // 检查是否有候选歌词
      if (candidatesResult['candidates'] == null ||
          candidatesResult['candidates'].isEmpty) {
        _currentLyrics = [];
        _notifyListeners();
        return;
      }

      // 获取第一个候选歌词的id和accesskey
      final lyricId = candidatesResult['candidates'][0]['id'].toString();
      final accessKey = candidatesResult['candidates'][0]['accesskey']
          .toString();

      // 第三步：获取加密的歌词内容
      final lyricUrl =
          'https://lyrics.kugou.com/download?ver=1&id=$lyricId&accesskey=$accessKey&fmt=lrc';
      final lyricUri = Uri.parse(lyricUrl);

      final lyricResponse = await http
          .get(lyricUri)
          .timeout(const Duration(seconds: 10));

      // 如果状态码不为200，清空并返回
      if (lyricResponse.statusCode != 200) {
        _currentLyrics = [];
        _notifyListeners();
        return;
      }

      final lyricResult = json.decode(lyricResponse.body);

      // 检查是否有歌词内容
      if (lyricResult['content'] == null) {
        _currentLyrics = [];
        _notifyListeners();
        return;
      }

      // 第四步：解码base64歌词
      final base64Lyric = lyricResult['content'].toString();
      final decodedLyric = utf8.decode(base64Decode(base64Lyric));

      // 解析歌词
      _currentLyrics = _parseLrcContent([decodedLyric]);
    } catch (e) {
      _currentLyrics = [];
    }
    _notifyListeners();
  }

  // 企鹅音乐歌词获取方法
  Future<void> _loadQQLyrics(String songTitle, {String? queryOverride}) async {
    try {
      // 检查 artist 是否为默认值，如果是则设置为空字符串
      final rawArtist = _getCurrentSong()?.artist ?? '';
      final artist = (rawArtist == '未知歌手' || rawArtist == '未知歌手 (解析失败)')
          ? ''
          : rawArtist;

      // 组合搜索关键词（有歌手时：歌手 - 歌名；否则只用歌名）
      final searchKeyword =
          queryOverride ??
          (artist.isEmpty
              ? songTitle.trim()
              : '${artist.trim()} - ${songTitle.trim()}');

      // 第一步：搜索歌曲
      const searchUrl = 'https://u.y.qq.com/cgi-bin/musicu.fcg';
      final searchBody = jsonEncode({
        "comm": {"ct": "19", "cv": "1873", "uin": "0"},
        "music.search.SearchCgiService": {
          "method": "DoSearchForQQMusicDesktop",
          "module": "music.search.SearchCgiService",
          "param": {
            "grp": 1,
            "num_per_page": 40,
            "page_num": 1,
            "query": searchKeyword,
            "search_type": 0,
          },
        },
      });

      final searchRequest = http.Request('POST', Uri.parse(searchUrl))
        ..headers['User-Agent'] =
            'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)'
        ..body = searchBody;

      final searchStreamedResponse = await http.Client().send(searchRequest);
      final searchResponse = await http.Response.fromStream(
        searchStreamedResponse,
      );

      if (searchResponse.statusCode != 200) {
        _currentLyrics = [];
        _notifyListeners();
        return;
      }

      // 直接使用bodyBytes避免Content-Type解析问题
      final searchResult = json.decode(utf8.decode(searchResponse.bodyBytes));

      // 检查搜索结果
      if (searchResult['music.search.SearchCgiService'] == null ||
          searchResult['music.search.SearchCgiService']['data'] == null ||
          searchResult['music.search.SearchCgiService']['data']['body'] ==
              null ||
          searchResult['music.search.SearchCgiService']['data']['body']['song'] ==
              null ||
          searchResult['music.search.SearchCgiService']['data']['body']['song']['list'] ==
              null ||
          searchResult['music.search.SearchCgiService']['data']['body']['song']['list']
              .isEmpty) {
        _currentLyrics = [];
        _notifyListeners();
        return;
      }

      // 获取第一首歌曲的信息
      final songList =
          searchResult['music.search.SearchCgiService']['data']['body']['song']['list'];
      final firstSong = songList[0];
      final songMid = firstSong['mid'].toString();
      final musicId = firstSong['id'].toString();

      // 第二步：获取歌词
      final lyricUrl = Uri.parse(
        'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg'
        '?songmid=$songMid'
        '&musicid=$musicId'
        '&format=json'
        '&g_tk=5381',
      );

      final lyricRequest = http.Request('GET', lyricUrl)
        ..headers['Referer'] = 'https://y.qq.com/n/ryqq/player'
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.5005.63 Safari/537.36';

      final lyricStreamedResponse = await http.Client().send(lyricRequest);
      final lyricResponse = await http.Response.fromStream(
        lyricStreamedResponse,
      );

      if (lyricResponse.statusCode != 200) {
        _currentLyrics = [];
        _notifyListeners();
        return;
      }

      // 手动处理响应体，避免因Content-Type导致的解析问题
      final lyricResult = json.decode(utf8.decode(lyricResponse.bodyBytes));

      // 处理歌词内容
      List<String> lrcLines = [];
      if (lyricResult['lyric'] != null) {
        try {
          final lyricBase64 = lyricResult['lyric'];
          final lyricData = utf8.decode(base64Decode(lyricBase64));
          lrcLines = lyricData.split('\n');
        } catch (e) {
          //
        }
      }

      // 处理翻译歌词内容
      List<String> tlyricLines = [];
      if (lyricResult['trans'] != null && lyricResult['trans'].isNotEmpty) {
        try {
          final transBase64 = lyricResult['trans'];
          final transData = utf8.decode(base64Decode(transBase64));
          tlyricLines = transData.split('\n');
        } catch (e) {
          //
        }
      }

      // 合并歌词
      final List<String> mergedLyrics = [];
      mergedLyrics.addAll(lrcLines);

      if (tlyricLines.isNotEmpty) {
        mergedLyrics.add(''); // 空行分隔
        mergedLyrics.addAll(tlyricLines);
      }

      // 解析歌词
      _currentLyrics = _parseLrcContent(mergedLyrics);
    } catch (e) {
      _currentLyrics = [];
    }
    _notifyListeners();
  }

  // 解析歌词
  List<LyricLine> _parseLrcContent(List<String> lines) {
    // 检查是否有awlrc标签，如果有则优先使用awlrc解析的结果
    final awlrcResult = _checkAndParseAwlrcFirst(lines);
    if (awlrcResult != null) {
      return awlrcResult;
    }

    final Map<Duration, List<String>> groupedLyrics = {};
    final Map<Duration, List<List<LyricToken>>> karaokeTokenMap = {};

    // 兼容不带毫秒的时间戳格式（到底是谁在用这种）
    final RegExp timeStampRegExp = RegExp(
      r'\[(\d{1,2}):(\d{2})[.:](\d{1,3})\](.*)',
    );

    for (final line in lines) {
      final matches = timeStampRegExp.allMatches(line);

      // 跳过无时间戳的行
      if (matches.isEmpty) {
        continue;
      }

      // 只处理每行的第一个时间戳作为该行的起始时间
      // 行内后续的时间戳会被 _parseKaraokeTokens 识别为逐字标记
      final match = matches.first;

      try {
        final int minutes = int.parse(match.group(1)!);
        final int seconds = int.parse(match.group(2)!);
        // 处理可选的毫秒部分
        final int milliseconds = match.group(3) != null
            ? int.parse(match.group(3)!.padRight(3, '0'))
            : 0;
        final Duration timestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        // 获取歌词内容
        final String rawText = match.group(4)!.trim();

        // 跳过双斜杠
        if (rawText == '//' || rawText.replaceAll(RegExp(r'\s+'), '') == '//') {
          continue;
        }

        // 检查是否为逐字歌词格式
        if (_isKaraokeLyric(rawText)) {
          final tokens = _parseKaraokeTokens(rawText, timestamp);
          final displayText = _extractDisplayText(rawText);

          if (displayText.isNotEmpty) {
            // 添加到对应时间戳的文本列表中
            groupedLyrics.putIfAbsent(timestamp, () => []).add(displayText);
          }

          // 将当前行的tokens添加到列表中，而不是覆盖
          // 这样可以支持多行共享同一时间戳的逐字歌词
          if (tokens.isNotEmpty) {
            karaokeTokenMap.putIfAbsent(timestamp, () => []).add(tokens);
          }
        } else {
          // 清除普通歌词里的时间标记（ <> [] () ）
          // 这里是为了解析逐字歌词失败时不被时间标记所污染
          final String cleanedText = rawText.replaceAll(
            RegExp(
              r'(<\d{2}:\d{2}\.\d{2,3}>|\[\d{2}:\d{2}\.\d{2,3}\]|\(\d{2}:\d{2}\.\d{2,3}\))',
            ),
            '',
          );

          if (cleanedText.isEmpty) {
            groupedLyrics.putIfAbsent(timestamp, () => []);
            continue;
          }
          groupedLyrics.putIfAbsent(timestamp, () => []).add(cleanedText);
        }
      } catch (e) {
        _notificationService.error('无法解析当前歌词');
      }
    }

    final List<LyricLine> parsedLyrics =
        groupedLyrics.entries
            .map(
              (entry) => LyricLine(
                timestamp: entry.key,
                texts: entry.value,
                tokens: karaokeTokenMap[entry.key],
              ),
            )
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return _processInterludes(parsedLyrics);
  }

  List<LyricLine>? _checkAndParseAwlrcFirst(List<String> lines) {
    for (final line in lines) {
      if (line.startsWith('[awlrc:')) {
        final RegExp awlrcRegExp = RegExp(r'\[awlrc:(.*?)\]');
        final match = awlrcRegExp.firstMatch(line);
        if (match != null) {
          final content = match.group(1)!;
          final parts = content.split(',');

          for (final part in parts) {
            if (part.startsWith('awlrc:')) {
              // 包含awlrc.awlrc字段才进入LX的歌词解析逻辑
              // 因为不包含的已经有普通的lrc 没必要再解析一次
              return _parseAwlrcContent(lines);
            }
          }
        }
      }
    }
    // 返回null表示继续使用普通解析逻辑
    return null;
  }

  // 解析包含awlrc标签的歌词内容
  List<LyricLine> _parseAwlrcContent(List<String> lines) {
    final Map<Duration, List<String>> groupedLyrics = {};
    final Map<Duration, List<List<LyricToken>>> karaokeTokenMap = {};

    final List<String> processedLines = _preprocessLrcLines(lines);

    // 兼容不带毫秒的时间戳格式（到底是谁在用这种）
    final RegExp timeStampRegExp = RegExp(
      r'\[(\d{1,2}):(\d{2})[.:](\d{1,3})\](.*)',
    );

    for (final line in processedLines) {
      final matches = timeStampRegExp.allMatches(line);

      // 跳过无时间戳的行
      if (matches.isEmpty) {
        continue;
      }

      // 只处理每行的第一个时间戳作为该行的起始时间
      // 行内后续的时间戳会被 _parseKaraokeTokens 识别为逐字标记
      final match = matches.first;

      try {
        final int minutes = int.parse(match.group(1)!);
        final int seconds = int.parse(match.group(2)!);
        // 处理可选的毫秒部分
        final int milliseconds = match.group(3) != null
            ? int.parse(match.group(3)!.padRight(3, '0'))
            : 0;
        final Duration timestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        // 获取歌词内容
        final String rawText = match.group(4)!.trim();

        // 跳过双斜杠
        if (rawText == '//' || rawText.replaceAll(RegExp(r'\s+'), '') == '//') {
          continue;
        }

        // 检查是否为逐字歌词格式
        if (_isKaraokeLyric(rawText)) {
          final tokens = _parseKaraokeTokens(rawText, timestamp);
          final displayText = _extractDisplayText(rawText);

          if (displayText.isNotEmpty) {
            // 添加到对应时间戳的文本列表中
            groupedLyrics.putIfAbsent(timestamp, () => []).add(displayText);
          }

          // 将当前行的tokens添加到列表中，而不是覆盖
          // 这样可以支持多行共享同一时间戳的逐字歌词
          if (tokens.isNotEmpty) {
            karaokeTokenMap.putIfAbsent(timestamp, () => []).add(tokens);
          }
        } else {
          // 清除普通歌词里的时间标记（ <> [] () ）
          // 这里是为了解析逐字歌词失败时不被时间标记所污染
          final String cleanedText = rawText.replaceAll(
            RegExp(
              r'(<\d{2}:\d{2}\.\d{2,3}>|\[\d{2}:\d{2}\.\d{2,3}\]|\(\d{2}:\d{2}\.\d{2,3}\))',
            ),
            '',
          );

          if (cleanedText.isEmpty) {
            groupedLyrics.putIfAbsent(timestamp, () => []);
            continue;
          }
          groupedLyrics.putIfAbsent(timestamp, () => []).add(cleanedText);
        }
      } catch (e) {
        _notificationService.error('无法解析当前歌词');
      }
    }

    final List<LyricLine> parsedLyrics =
        groupedLyrics.entries
            .map(
              (entry) => LyricLine(
                timestamp: entry.key,
                texts: entry.value,
                tokens: karaokeTokenMap[entry.key],
              ),
            )
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return _processInterludes(parsedLyrics);
  }

  // 处理间奏
  List<LyricLine> _processInterludes(List<LyricLine> lines) {
    if (lines.isEmpty) return lines;

    final List<LyricLine> result = [];

    int firstRealIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].isKaraoke || lines[i].texts.isNotEmpty) {
        firstRealIndex = i;
        break;
      }
    }

    if (firstRealIndex == -1) {
      return lines;
    }

    // 检查第零秒到第一句真实歌词之间是否大于 8 秒，如果是则插入间奏
    final firstReal = lines[firstRealIndex];
    if (firstReal.timestamp.inMilliseconds > 8000) {
      result.add(
        LyricLine(
          timestamp: Duration.zero,
          texts: [],
          isInterlude: true,
          interludeDuration: firstReal.timestamp,
        ),
      );
    }

    // 遍历 lines，把真实歌词加入 result，并在真实歌词之间检测并插入间奏
    for (int i = firstRealIndex; i < lines.length; i++) {
      final currentLine = lines[i];
      final isCurrentReal =
          currentLine.isKaraoke || currentLine.texts.isNotEmpty;

      if (isCurrentReal) {
        result.add(currentLine);

        // 寻找下一句真实歌词
        int nextRealIndex = -1;
        for (int j = i + 1; j < lines.length; j++) {
          if (lines[j].isKaraoke || lines[j].texts.isNotEmpty) {
            nextRealIndex = j;
            break;
          }
        }

        if (nextRealIndex != -1) {
          final nextReal = lines[nextRealIndex];

          // 确定当前真实歌词的结束/清除时间
          Duration currentEndTime;
          if (currentLine.isKaraoke) {
            currentEndTime = currentLine.timestamp;
            if (currentLine.tokens != null) {
              for (final tokenList in currentLine.tokens!) {
                for (final token in tokenList) {
                  if (token.end > currentEndTime) {
                    currentEndTime = token.end;
                  }
                }
              }
            }
          } else {
            // 普通歌词：如果在当前真实行与下一真实行之间存在空歌词占位，则以第一个空歌词时间戳为结束时间
            Duration? firstEmptyTimestamp;
            for (int j = i + 1; j < nextRealIndex; j++) {
              if (!lines[j].isKaraoke && lines[j].texts.isEmpty) {
                firstEmptyTimestamp = lines[j].timestamp;
                break;
              }
            }
            currentEndTime = firstEmptyTimestamp ?? nextReal.timestamp;
          }

          // 计算空档时间
          final gap = nextReal.timestamp - currentEndTime;
          if (gap.inMilliseconds > 8000) {
            result.add(
              LyricLine(
                timestamp: currentEndTime,
                texts: [],
                isInterlude: true,
                interludeDuration: gap,
              ),
            );
          }
        }
      }
    }

    return result;
  }

  // 预处理LRC行，处理awlrc标签
  List<String> _preprocessLrcLines(List<String> lines) {
    final List<String> result = [];
    final List<String> awlrcLines = [];

    for (final line in lines) {
      if (line.startsWith('[awlrc:')) {
        awlrcLines.addAll(_parseAwlrcTag(line));
      } else {
        // 普通行直接跳过（因为awlrc优先级最高，会替换其他歌词）
        continue;
      }
    }

    // 将awlrc解析后的内容添加到结果中
    result.addAll(awlrcLines);

    return result;
  }

  // 解析awlrc标签
  List<String> _parseAwlrcTag(String tagLine) {
    final List<String> result = [];

    // 匹配awlrc标签格式
    final RegExp awlrcRegExp = RegExp(r'\[awlrc:(.*?)\]');
    final match = awlrcRegExp.firstMatch(tagLine);

    if (match != null) {
      final content = match.group(1)!;
      final parts = content.split(',');

      final Map<String, String> partsMap = {};
      for (final part in parts) {
        final colonIndex = part.indexOf(':');
        if (colonIndex > 0) {
          final key = part.substring(0, colonIndex);
          final value = part.substring(colonIndex + 1);
          partsMap[key] = value;
        }
      }

      // 处理LX的逐字歌词(awlrc.awlrc)
      if (partsMap.containsKey('awlrc')) {
        final awlrcContent = partsMap['awlrc']!;
        try {
          final decodedContent = utf8.decode(base64Decode(awlrcContent));
          result.addAll(_convertLxLyricsToStandardFormat(decodedContent));
        } catch (e) {
          //
        }
      }

      // 处理翻译歌词(awlrc.tlrc)
      if (partsMap.containsKey('tlrc')) {
        final tlrcContent = partsMap['tlrc']!;
        try {
          final decodedContent = utf8.decode(base64Decode(tlrcContent));
          result.addAll(decodedContent.split('\n'));
        } catch (e) {
          //
        }
      }

      // 处理罗马音歌词(awlrc.rlrc)
      if (partsMap.containsKey('rlrc')) {
        final rlrcContent = partsMap['rlrc']!;
        try {
          final decodedContent = utf8.decode(base64Decode(rlrcContent));
          result.addAll(decodedContent.split('\n'));
        } catch (e) {
          //
        }
      }
    }

    // 不需要普通歌词(awlrc.lrc) 因为LX的逐字歌词(awlrc.awlrc)已经包含了
    // 对于没有LX的逐字歌词(awlrc.awlrc)的情况 仍然不需要普通歌词(awlrc.lrc)
    // 因为普通lrc已经包含了歌词

    return result;
  }

  // 将LX格式的歌词转换为标准格式
  List<String> _convertLxLyricsToStandardFormat(String lxLyrics) {
    final List<String> result = [];
    final lines = lxLyrics.split('\n');

    for (final line in lines) {
      // 格式：[分钟:秒.毫秒]<开始时间（基于该句）,持续时间>歌词文字
      // 例如：[00:10.124]<0,248>嫌<248,313>菜<561,288>煮<849,296>了
      final RegExp lxLyricsRegExp = RegExp(
        r'\[(\d{2}):(\d{2})\.(\d{1,3})\](.*)',
      );
      final match = lxLyricsRegExp.firstMatch(line);

      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        // 处理不足3位的毫秒数，例如 40->400
        final millisecondsStr = match.group(3)!.padRight(3, '0');
        final milliseconds = int.parse(millisecondsStr);
        final content = match.group(4)!;

        final baseTimestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        // 解析歌词内容部分，格式为<开始时间,持续时间>文字
        final RegExp timeTagRegExp = RegExp(r'<(\d+),(\d+)>');
        final timeMatches = timeTagRegExp.allMatches(content).toList();

        if (timeMatches.isNotEmpty) {
          final StringBuffer convertedLine = StringBuffer(
            '[${_formatTime(baseTimestamp)}]',
          );
          // 记录上一个片段的绝对结束时间，初始值为该句起始点
          Duration lastAbsoluteEnd = baseTimestamp;

          for (int i = 0; i < timeMatches.length; i++) {
            final timeMatch = timeMatches[i];
            final relativeStart = int.parse(timeMatch.group(1)!);
            final durationMs = int.parse(timeMatch.group(2)!);

            final absoluteStart =
                baseTimestamp + Duration(milliseconds: relativeStart);
            final absoluteEnd =
                absoluteStart + Duration(milliseconds: durationMs);

            if (absoluteStart > lastAbsoluteEnd) {
              // 如果当前字开始时间晚于上个字结束时间，说明中间有空白
              // _parseKaraokeTokens 会正确处理该情况
              convertedLine.write('<${_formatTime(lastAbsoluteEnd)}>');
            }

            final textStart = timeMatch.end;
            final textEnd = (i + 1 < timeMatches.length)
                ? timeMatches[i + 1].start
                : content.length;
            final String text = content.substring(textStart, textEnd);

            convertedLine.write('<${_formatTime(absoluteStart)}>$text');

            lastAbsoluteEnd = absoluteEnd;

            if (i == timeMatches.length - 1) {
              convertedLine.write('<${_formatTime(absoluteEnd)}>');
            }
          }
          result.add(convertedLine.toString());
        } else {
          result.add(line);
        }
      } else {
        result.add(line);
      }
    }

    return result;
  }

  // 格式化时间为[mm:ss.mmm]格式
  String _formatTime(Duration duration) {
    final int totalSeconds = duration.inSeconds;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    final int milliseconds = duration.inMilliseconds % 1000;

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${milliseconds.toString().padLeft(3, '0')}';
  }

  // 检测是否为逐字歌词格式
  bool _isKaraokeLyric(String text) {
    if (RegExp(r'<\d+:\d+').hasMatch(text)) return true;
    return RegExp(r'\[\d{2}:\d{2}(\.\d+)?\]').hasMatch(text);
  }

  // 从逐字歌词中提取显示文本
  String _extractDisplayText(String rawText) {
    // 移除所有时间戳标记，保留纯文本内容
    return rawText
        .replaceAll(
          RegExp(
            r'<\d{2}:\d{2}\.\d{2,3}>|\[\d{2}:\d{2}\.\d{2,3}\]|\(\d{2}:\d{2}\.\d{2,3}\)',
          ),
          '',
        )
        .trim();
  }

  List<LyricToken> _parseKaraokeTokens(String rawText, Duration lineStart) {
    final List<LyricToken> tokens = [];

    final RegExp inline = RegExp(r'<(\d{2}):(\d{2})\.(\d{2,3})>');
    final RegExp bracket = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

    final matches = <Match>[
      ...inline.allMatches(rawText),
      ...bracket.allMatches(rawText),
    ]..sort((a, b) => a.start.compareTo(b.start));

    // 如果只有一个时间戳，持续0毫秒跳过动画
    if (matches.length == 1) {
      final displayText = _extractDisplayText(rawText);
      if (displayText.isNotEmpty) {
        tokens.add(
          LyricToken(
            text: displayText,
            start: lineStart,
            end: lineStart + const Duration(milliseconds: 0),
          ),
        );
      }
      return tokens;
    }

    Duration? pendingStart = lineStart;
    int lastIndex = 0;

    for (final match in matches) {
      final text = rawText.substring(lastIndex, match.start);
      final time = _parseTimestamp(match);

      if (text.isNotEmpty) {
        // 前置时间戳：text的start在pendingStart
        tokens.add(
          LyricToken(
            text: text,
            start: pendingStart!,
            end: time, // 暂定为end
          ),
        );
        pendingStart = time;
      } else {
        if (tokens.isNotEmpty && pendingStart != null && time > pendingStart) {
          tokens.add(
            LyricToken(
              // 假设以下歌词格式：
              // [01:05.493]believer [01:06.380][01:07.461]believer[01:08.285]
              // 有两个时间戳中间没有任何内容
              // 等价于[01:05.493]believer[01:06.380] [01:07.461]believer[01:08.285]
              // 本质上是为了让ui渲染完后第1个believer停顿一下再渲染下一个believer
              // 但是由于ui是连续的，所以这里添加一个不可见的字符给ui来模拟停顿
              text: '\u200B', // 不可见字符
              start: pendingStart,
              end: time,
            ),
          );
        }
        pendingStart = time;
      }

      lastIndex = match.end;
    }

    // 处理最后一段文本
    if (lastIndex < rawText.length) {
      final text = rawText.substring(lastIndex);
      if (text.isNotEmpty) {
        tokens.add(
          LyricToken(
            text: text,
            start: pendingStart!,
            end: Duration.zero, // 暂空
          ),
        );
      }
    }

    // 统一补 end
    for (int i = 0; i < tokens.length; i++) {
      if (tokens[i].end == Duration.zero) {
        if (i + 1 < tokens.length) {
          tokens[i] = LyricToken(
            text: tokens[i].text,
            start: tokens[i].start,
            end: tokens[i + 1].start,
          );
        } else {
          tokens[i] = LyricToken(
            text: tokens[i].text,
            start: tokens[i].start,
            end: _fallbackEndForToken(tokens[i].start),
          );
        }
      }
    }

    return tokens;
  }

  // 统一解析 match 中的时间
  Duration _parseTimestamp(Match match) {
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final millisecondsStr = match.group(3)!;
    final milliseconds = int.parse(millisecondsStr.padRight(3, '0'));
    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  // 为token提供一个合理的结束时间fallback
  Duration _fallbackEndForToken(Duration start) {
    return start +
        const Duration(milliseconds: 500); // 使用token开始时间+500ms作为默认持续时间
  }

  void updateLyricLine(Duration currentPosition) {
    if (_currentLyrics.isEmpty) {
      if (_currentLyricLineIndex != -1) {
        _currentLyricLineIndex = -1;
        _lyricLineIndexController.add(-1); // 广播空歌词状态
      }
      return;
    }

    // 使用二分查找查找当前歌词行
    int newIndex = -1;
    int left = 0;
    int right = _currentLyrics.length - 1;

    while (left <= right) {
      final int mid = (left + right) ~/ 2;
      if (currentPosition >= _currentLyrics[mid].timestamp) {
        if (mid + 1 >= _currentLyrics.length ||
            currentPosition < _currentLyrics[mid + 1].timestamp) {
          newIndex = mid;
          break;
        }
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }

    // // 如果当前是暂停状态，则开始播放
    // if (!_isPlaying) {
    //   _audioService.player.play();
    // }

    if (newIndex != _currentLyricLineIndex) {
      _currentLyricLineIndex = newIndex;
      _lyricLineIndexController.add(newIndex); // 广播新索引
    }
  }
}
