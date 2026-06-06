import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:audioplayers/audioplayers.dart';
import 'package:id3_codec/id3_codec.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:palette_generator/palette_generator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  runApp(const MyMusicApp());
}

class MyMusicApp extends StatefulWidget {
  const MyMusicApp({super.key});

  @override
  State<MyMusicApp> createState() => _MyMusicAppState();
}

class _MyMusicAppState extends State<MyMusicApp> {
  Color _accentColor = const Color(0xFFD4AF37);
  Color _accentContainerColor = const Color(0xFF252114);

  void _updateThemeColor(Color major, Color container) {
    setState(() {
      _accentColor = major;
      _accentContainerColor = container;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Gio's Music App",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        colorScheme: ColorScheme.dark(
          primary: _accentColor,
          secondary: _accentColor.withOpacity(0.7),
          surface: const Color(0xFF161616),
          onSurface: Colors.white,
          primaryContainer: _accentContainerColor,
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFF2A2A2A)),
      ),
      home: MusicPlayerHomePage(onThemeChanged: _updateThemeColor),
    );
  }
}

class MusicPlayerHomePage extends StatefulWidget {
  final Function(Color, Color) onThemeChanged;
  const MusicPlayerHomePage({super.key, required this.onThemeChanged});

  @override
  State<MusicPlayerHomePage> createState() => _MusicPlayerHomePageState();
}

class _MusicPlayerHomePageState extends State<MusicPlayerHomePage> with TickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _lyricsScrollController = ScrollController();

  late AnimationController _waveAnimationController;
  late AnimationController _visualizerController;

  bool _isPlaying = false;
  bool _isQueueOpen = true;
  bool _isScanning = false;
  bool _isShuffleOn = false;
  bool _isLoopOn = false;

  bool _isWaveForm = true;
  double _timelineThickness = 3.0;
  bool _isRecordPlayerMode = true;
  double _spinSpeedFactor = 1.0;
  double _animationSpeedFactor = 1.0; 

  bool _autoAdvanceNext = true;
  double _waveSpeedFactor = 1.0;
  double _volume = 0.8;
  int _sidebarTab = 0; 

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  Map<String, List<File>> _groupedPlaylist = {};
  List<File> _flatTrackList = [];
  List<int> _shuffledIndices = [];
  int _currentIndex = -1;

  String _currentTrackName = "No tracks loaded";
  String _searchQuery = "";
  Uint8List? _albumArtBytes;
  ui.Image? _decodedVinylImage;

  // Scratch / drag interaction parameters
  double _dragStartAngle = 0.0;
  double _dragLastAngle = 0.0;

  // A-B Segment Looping state parameters
  Duration? _loopA;
  Duration? _loopB;
  bool _isABLoopActive = false;

  // LRC Lyrics parsing and tracking state
  List<LyricLine> _lyrics = [];
  int _activeLyricIndex = -1;
  bool _showLyrics = false;

  // Keyboard Command Actions map metadata
  final Map<String, String> _actionLabels = {
    'play_pause': 'Play / Pause',
    'seek_forward': 'Seek Forward (+5s)',
    'seek_backward': 'Seek Backward (-5s)',
    'volume_up': 'Volume Up (+5%)',
    'volume_down': 'Volume Down (-5%)',
    'set_loop_a': 'Set Loop Point A',
    'set_loop_b': 'Set Loop Point B',
    'clear_loop': 'Clear Loop Points',
  };

  late Map<String, LogicalKeyboardKey> _keybinds;
  String? _rebindingAction; 

  @override
  void initState() {
    super.initState();
    _waveAnimationController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _visualizerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();

    _keybinds = {
      'play_pause': LogicalKeyboardKey.space,
      'seek_forward': LogicalKeyboardKey.arrowRight,
      'seek_backward': LogicalKeyboardKey.arrowLeft,
      'volume_up': LogicalKeyboardKey.arrowUp,
      'volume_down': LogicalKeyboardKey.arrowDown,
      'set_loop_a': LogicalKeyboardKey.keyI,
      'set_loop_b': LogicalKeyboardKey.keyO,
      'clear_loop': LogicalKeyboardKey.keyC,
    };

    _setupAudioListeners();
    _autoScanSystemMusic();
  }

  void _updateAnimationSpeed(double speed) {
    setState(() {
      _animationSpeedFactor = speed;
      _waveAnimationController.duration = Duration(milliseconds: (2000 / speed).toInt());
      _visualizerController.duration = Duration(milliseconds: (1500 / speed).toInt());
      _waveAnimationController.repeat();
      _visualizerController.repeat();
    });
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;

    if (_rebindingAction != null) {
      setState(() {
        _keybinds[_rebindingAction!] = key;
        _rebindingAction = null;
      });
      return KeyEventResult.handled;
    }

    final bool isTyping = FocusManager.instance.primaryFocus?.context?.widget is EditableText ||
                          FocusManager.instance.primaryFocus?.debugLabel?.contains('EditableText') == true;

    if (isTyping) {
      return KeyEventResult.ignored;
    }

    String? triggeredAction;
    _keybinds.forEach((action, boundKey) {
      if (boundKey == key) {
        triggeredAction = action;
      }
    });

    if (triggeredAction != null) {
      _executeAction(triggeredAction!);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _executeAction(String action) {
    switch (action) {
      case 'play_pause':
        _togglePlayPause();
        break;
      case 'seek_forward':
        _seekRelative(const Duration(seconds: 5));
        break;
      case 'seek_backward':
        _seekRelative(const Duration(seconds: -5));
        break;
      case 'volume_up':
        _adjustVolume(0.05);
        break;
      case 'volume_down':
        _adjustVolume(-0.05);
        break;
      case 'set_loop_a':
        _setLoopA();
        break;
      case 'set_loop_b':
        _setLoopB();
        break;
      case 'clear_loop':
        _clearABLoop();
        break;
    }
  }

  void _seekRelative(Duration offset) {
    if (_duration == Duration.zero) return;
    final target = _position + offset;
    final clamped = Duration(
      milliseconds: target.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );
    _audioPlayer.seek(clamped);
  }

  void _adjustVolume(double delta) {
    setState(() {
      _volume = (_volume + delta).clamp(0.0, 1.0);
      _audioPlayer.setVolume(_volume);
    });
  }

  void _setLoopA() {
    if (_duration == Duration.zero) return;
    setState(() {
      _loopA = _position;
      if (_loopB != null && _loopB! <= _loopA!) {
        _loopB = null;
        _isABLoopActive = false;
      }
    });
  }

  void _setLoopB() {
    if (_duration == Duration.zero || _loopA == null) return;
    setState(() {
      if (_position > _loopA!) {
        _loopB = _position;
        _isABLoopActive = true;
      }
    });
  }

  void _clearABLoop() {
    setState(() {
      _loopA = null;
      _loopB = null;
      _isABLoopActive = false;
    });
  }

  void _scrollToActiveLyric() {
    if (!_showLyrics || _lyrics.isEmpty || _activeLyricIndex == -1) return;
    if (_lyricsScrollController.hasClients) {
      const double itemHeight = 44.0;
      const double viewportHeight = 290.0;
      final double targetScroll = (_activeLyricIndex * itemHeight) - (viewportHeight / 2) + (itemHeight / 2);
      _lyricsScrollController.animateTo(
        targetScroll.clamp(0.0, _lyricsScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _setupAudioListeners() {
    _audioPlayer.setVolume(_volume);

    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) setState(() => _duration = newDuration);
    });

    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (!mounted) return;

      int newActiveIndex = -1;
      for (int i = 0; i < _lyrics.length; i++) {
        if (newPosition >= _lyrics[i].timestamp) {
          newActiveIndex = i;
        } else {
          break;
        }
      }

      setState(() {
        _position = newPosition;
        if (_activeLyricIndex != newActiveIndex) {
          _activeLyricIndex = newActiveIndex;
          _scrollToActiveLyric();
        }

        if (_isABLoopActive && _loopA != null && _loopB != null) {
          if (_position >= _loopB! || _position < _loopA!) {
            _audioPlayer.seek(_loopA!);
          }
        }
      });
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      if (!mounted) return;
      if (_isLoopOn) {
        _audioPlayer.seek(Duration.zero);
        _audioPlayer.resume();
      } else if (_autoAdvanceNext) {
        _skipForward();
      } else {
        setState(() {
          _isPlaying = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _searchController.dispose();
    _lyricsScrollController.dispose();
    _waveAnimationController.dispose();
    _visualizerController.dispose();
    super.dispose();
  }

  Future<void> _decodeVinylImage(Uint8List bytes) async {
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      completer.complete(img);
    });
    final decoded = await completer.future;
    if (mounted) {
      setState(() {
        _decodedVinylImage = decoded;
      });
    }
  }

  Future<void> _loadStoredLibrary() async {
    await _autoScanSystemMusic();
  }

  Future<void> _clearCacheAndRescan() async {
    setState(() {
      _isScanning = true;
      _albumArtBytes = null;
      _decodedVinylImage = null;
      _searchController.clear();
      _searchQuery = "";
      _clearABLoop();
    });
    
    try {
      await MetadataService.scanMusic(); 
    } catch (e) {
      debugPrint("MetadataService scan failed: $e");
    }
    
    await _loadStoredLibrary(); 
    setState(() => _isScanning = false);
  }

  Future<void> _autoScanSystemMusic() async {
    setState(() => _isScanning = true);
    try {
      final String homePath = Platform.environment['HOME'] ?? '';
      if (homePath.isEmpty) {
        setState(() => _currentTrackName = "Could not locate home path");
        return;
      }

      final List<Directory> targetDirs = [
        Directory('$homePath/Music'),
        Directory('$homePath/Downloads'),
      ];

      Map<String, List<File>> temporaryGrouped = {};

      for (var dir in targetDirs) {
        if (await dir.exists()) {
          await for (var entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              final String path = entity.path.toLowerCase();
              if (path.endsWith('.mp3') || path.endsWith('.wav') || path.endsWith('.m4a')) {
                final String parentFolderPath = entity.parent.path;
                
                if (!temporaryGrouped.containsKey(parentFolderPath)) {
                  temporaryGrouped[parentFolderPath] = [];
                }
                temporaryGrouped[parentFolderPath]!.add(entity);

                List<File> workingFlat = [];
                temporaryGrouped.values.forEach((list) => workingFlat.addAll(list));

                setState(() {
                  _groupedPlaylist = Map.from(temporaryGrouped);
                  _flatTrackList = workingFlat;
                  _generateShuffleSequence();
                });
              }
            }
          }
        }
      }

      _groupedPlaylist.forEach((folder, files) {
        files.sort((a, b) => a.path.split('/').last.compareTo(b.path.split('/').last));
      });

      setState(() => _isScanning = false);

      if (_flatTrackList.isNotEmpty && _currentIndex == -1) {
        _loadTrack(0);
      } else if (_flatTrackList.isEmpty) {
        setState(() => _currentTrackName = "No tracks found in Music or Downloads");
      }
    } catch (e) {
      debugPrint("Directory indexing failed: $e");
      setState(() {
        _isScanning = false;
        _currentTrackName = "Scan error occurred";
      });
    }
  }

  void _generateShuffleSequence() {
    _shuffledIndices = List<int>.generate(_flatTrackList.length, (i) => i);
    if (_isShuffleOn) {
      _shuffledIndices.shuffle(Random());
    }
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffleOn = !_isShuffleOn;
      final File? currentFile = _currentIndex != -1 ? _flatTrackList[_currentIndex] : null;
      _generateShuffleSequence();
      if (currentFile != null) {
        _currentIndex = _flatTrackList.indexOf(currentFile);
      }
    });
  }

  Future<void> _loadTrack(int index) async {
    if (_flatTrackList.isEmpty || index < 0 || index >= _flatTrackList.length) return;

    final currentFile = _flatTrackList[index];
    setState(() {
      _currentIndex = index;
      _currentTrackName = currentFile.path.split('/').last;
      _albumArtBytes = null;
      _decodedVinylImage = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _clearABLoop();
      _lyrics = [];
      _activeLyricIndex = -1;
    });

    bool artFound = false;

    if (currentFile.path.toLowerCase().endsWith('.mp3')) {
      try {
        final fileBytes = await File(currentFile.path).readAsBytes();
        final decoder = ID3Decoder(fileBytes);
        final List<dynamic>? metadata = await decoder.decodeAsync();

        if (metadata != null) {
          for (var frame in metadata) {
            final String frameStr = frame.toString().toLowerCase();
            if (frameStr.contains('apic') || frameStr.contains('pic')) {
              try {
                dynamic content;
                try {
                  content = (frame as dynamic).content;
                } catch (_) {
                  if (frame is Map) {
                    content = frame['content'] ?? frame['Content'];
                  }
                }

                String? base64Str;
                if (content is Map) {
                  base64Str = content['base64'] ?? content['Base64'];
                }

                if (base64Str != null && base64Str.isNotEmpty) {
                  setState(() {
                    _albumArtBytes = base64Decode(base64Str!.trim());
                  });
                  artFound = true;
                  break; 
                }
              } catch (ex) {
                debugPrint("Failed to parse embedded artwork frame: $ex");
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Embedded thumbnail skip: $e");
      }
    }

    if (!artFound) {
      try {
        final Directory parentDir = currentFile.parent;
        final List<FileSystemEntity> folderContents = parentDir.listSync();
        final imageFile = folderContents.firstWhere(
          (entity) => RegExp(r'\.(jpg|jpeg|png)$').hasMatch(entity.path.toLowerCase()),
          orElse: () => currentFile,
        );
        if (imageFile != currentFile) {
          final Uint8List externalArt = await File(imageFile.path).readAsBytes();
          setState(() => _albumArtBytes = externalArt);
        }
      } catch (e) {
        debugPrint("Folder-art fallback skipped: $e");
      }
    }

    // Try finding matching .lrc synchronized lyrics file
    try {
      final String audioPath = currentFile.path;
      final int lastDotIdx = audioPath.lastIndexOf('.');
      if (lastDotIdx != -1) {
        final String lrcPath = audioPath.substring(0, lastDotIdx) + '.lrc';
        final File lrcFile = File(lrcPath);
        if (await lrcFile.exists()) {
          final List<String> lines = await lrcFile.readAsLines();
          final List<LyricLine> tempLyrics = [];
          final RegExp regExp = RegExp(r'\[(\d+):(\d+)(?:\.(\d+))?\](.*)');
          
          for (String line in lines) {
            final match = regExp.firstMatch(line);
            if (match != null) {
              final int minutes = int.parse(match.group(1)!);
              final int seconds = int.parse(match.group(2)!);
              final String? centiStr = match.group(3);
              final int centiseconds = centiStr != null ? int.parse(centiStr) : 0;
              final String text = match.group(4)!.trim();

              final Duration timestamp = Duration(
                minutes: minutes,
                seconds: seconds,
                milliseconds: centiseconds * 10,
              );
              tempLyrics.add(LyricLine(timestamp: timestamp, text: text));
            }
          }
          tempLyrics.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          setState(() {
            _lyrics = tempLyrics;
          });
        }
      }
    } catch (e) {
      debugPrint("Failed parsing LRC lyrics: $e");
    }

    if (_albumArtBytes != null) {
      final themeColors = await ThemeService.generateColorsFromImage(_albumArtBytes!);
      widget.onThemeChanged(themeColors['primary']!, themeColors['container']!);
      await _decodeVinylImage(_albumArtBytes!);
    }

    if (_isPlaying) {
      await _audioPlayer.play(DeviceFileSource(currentFile.path));
    } else {
      await _audioPlayer.stop();
      setState(() => _isPlaying = false);
    }
  }

  Future<void> _selectTrackDirectly(File targetedFile) async {
    int trackingIdx = _flatTrackList.indexOf(targetedFile);
    if (trackingIdx != -1) {
      setState(() => _isPlaying = true);
      _loadTrack(trackingIdx);
    }
  }

  Future<void> _togglePlayPause() async {
    if (_flatTrackList.isEmpty || _currentIndex == -1) return;

    if (_isPlaying) {
      await _audioPlayer.pause();
      setState(() => _isPlaying = false);
    } else {
      await _audioPlayer.play(DeviceFileSource(_flatTrackList[_currentIndex].path));
      setState(() => _isPlaying = true);
    }
  }

  void _skipBackward() {
    if (_flatTrackList.isEmpty) return;
    int nextIndex;
    if (_isShuffleOn) {
      int currentShufflePos = _shuffledIndices.indexOf(_currentIndex);
      int nextShufflePos = (currentShufflePos - 1 + _shuffledIndices.length) % _shuffledIndices.length;
      nextIndex = _shuffledIndices[nextShufflePos];
    } else {
      nextIndex = (_currentIndex - 1 + _flatTrackList.length) % _flatTrackList.length;
    }
    _loadTrack(nextIndex);
  }

  void _skipForward() {
    if (_flatTrackList.isEmpty) return;
    int nextIndex;
    if (_isShuffleOn) {
      int currentShufflePos = _shuffledIndices.indexOf(_currentIndex);
      int nextShufflePos = (currentShufflePos + 1) % _shuffledIndices.length;
      nextIndex = _shuffledIndices[nextShufflePos];
    } else {
      nextIndex = (_currentIndex + 1) % _flatTrackList.length;
    }
    _loadTrack(nextIndex);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  String _cleanFolderTitle(String fullPath) {
    final String homePath = Platform.environment['HOME'] ?? '';
    if (fullPath == '$homePath/Music') return "🎵 Standard Music Folder";
    if (fullPath == '$homePath/Downloads') return "📥 Downloads Directory";
    return "📂 ${fullPath.split('/').last}";
  }

  void _handleWaveScrub(Offset localPosition, double widgetWidth) {
    if (_duration == Duration.zero) return;
    double percentage = (localPosition.dx / widgetWidth).clamp(0.0, 1.0);
    int targetMilliseconds = (percentage * _duration.inMilliseconds).toInt();
    _audioPlayer.seek(Duration(milliseconds: targetMilliseconds));
  }

  double _calculateVinylAngle(Offset localPosition, Size widgetSize) {
    final double centerX = widgetSize.width / 2;
    final double centerY = widgetSize.height / 2;
    return atan2(localPosition.dy - centerY, localPosition.dx - centerX);
  }

  void _handleVinylScratchStart(Offset pos, Size size) {
    if (_duration == Duration.zero) return;
    _dragStartAngle = _calculateVinylAngle(pos, size);
    _dragLastAngle = _dragStartAngle;
  }

  void _handleVinylScratchUpdate(Offset pos, Size size) {
    if (_duration == Duration.zero) return;
    final double currentAngle = _calculateVinylAngle(pos, size);
    double deltaAngle = currentAngle - _dragLastAngle;
    
    if (deltaAngle > pi) deltaAngle -= 2 * pi;
    if (deltaAngle < -pi) deltaAngle += 2 * pi;

    final double continuousScrubRatio = deltaAngle / (2 * pi);
    final int msShift = (continuousScrubRatio * 25000 * _spinSpeedFactor).toInt(); 
    final int updatedPositionMs = (_position.inMilliseconds + msShift).clamp(0, _duration.inMilliseconds);
    
    _position = Duration(milliseconds: updatedPositionMs);
    _audioPlayer.seek(_position);
    _dragLastAngle = currentAngle;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Map<String, List<File>> filteredGroupedPlaylist = {};
    _groupedPlaylist.forEach((folderPath, files) {
      final String folderName = folderPath.split('/').last.toLowerCase();
      final matchingFiles = files.where((file) {
        final fileName = file.path.split('/').last.toLowerCase();
        return fileName.contains(_searchQuery.toLowerCase()) || folderName.contains(_searchQuery.toLowerCase());
      }).toList();
      if (matchingFiles.isNotEmpty) {
        filteredGroupedPlaylist[folderPath] = matchingFiles;
      }
    });

    double progressRatio = 0.0;
    if (_duration.inMilliseconds > 0) {
      progressRatio = (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    }

    double? loopARatio;
    double? loopBRatio;
    if (_duration.inMilliseconds > 0) {
      if (_loopA != null) loopARatio = _loopA!.inMilliseconds / _duration.inMilliseconds;
      if (_loopB != null) loopBRatio = _loopB!.inMilliseconds / _duration.inMilliseconds;
    }

    // Isolate Deck selection conditional block to guarantee parenthesized parsing safety
    Widget mainDeck;
    if (_showLyrics) {
      mainDeck = Container(
        width: 290,
        height: 290,
        decoration: BoxDecoration(
          color: const Color(0xFF111111).withOpacity(0.5),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.primary.withOpacity(0.15), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: _lyrics.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.subtitles_off_rounded, size: 40, color: Colors.white24),
                    const SizedBox(height: 12),
                    const Text(
                      "No Synced Lyrics Found",
                      style: TextStyle(fontSize: 13, color: Colors.white38, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Text(
                        "Place a .lrc file with the same name next to this song to view scrolling lyrics.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.15)),
                      ),
                    ),
                  ],
                ),
              )
            : ShaderMask(
                shaderCallback: (rect) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                    stops: [0.0, 0.15, 0.85, 1.0],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn,
                child: ListView.builder(
                  controller: _lyricsScrollController,
                  itemCount: _lyrics.length,
                  itemExtent: 44.0,
                  padding: const EdgeInsets.symmetric(vertical: 120.0),
                  itemBuilder: (context, idx) {
                    final lyric = _lyrics[idx];
                    final bool isActive = idx == _activeLyricIndex;
                    return Container(
                      height: 44.0,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        lyric.text,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isActive ? 16 : 13,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          color: isActive ? colors.primary : Colors.white.withOpacity(0.35),
                        ),
                      ),
                    );
                  },
                ),
              ),
      );
    } else if (_isRecordPlayerMode) {
      mainDeck = GestureDetector(
        onPanStart: (details) => _handleVinylScratchStart(details.localPosition, const Size(290, 290)),
        onPanUpdate: (details) => _handleVinylScratchUpdate(details.localPosition, const Size(290, 290)),
        child: RepaintBoundary(
          child: IsolatedVinylDeck(
            isPlaying: _isPlaying,
            spinSpeedFactor: _spinSpeedFactor,
            decodedImage: _decodedVinylImage, 
            primaryColor: colors.primary,
          ),
        ),
      );
    } else {
      mainDeck = RepaintBoundary(
        child: Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.primary.withOpacity(0.4), width: 1.5),
            boxShadow: [BoxShadow(color: colors.primary.withOpacity(0.08), blurRadius: 25, spreadRadius: 3)],
          ),
          clipBehavior: Clip.antiAlias,
          child: _albumArtBytes != null
              ? Image.memory(_albumArtBytes!, fit: BoxFit.cover)
              : Icon(Icons.music_note_rounded, size: 90, color: colors.primary.withOpacity(0.6)),
        ),
      );
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          return _handleKeyEvent(event);
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(_isQueueOpen ? Icons.menu_open_rounded : Icons.menu_rounded),
            color: colors.primary,
            tooltip: _isQueueOpen ? 'Hide Explorer' : 'Show Explorer',
            onPressed: () => setState(() => _isQueueOpen = !_isQueueOpen),
          ),
          title: Text(
            "GIO'S MUSIC WORKSTATION",
            style: TextStyle(color: colors.primary, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF111111),
          elevation: 0,
          actions: [
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.settings_suggest_rounded),
                color: colors.primary,
                tooltip: 'Open Settings Deck',
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
            const SizedBox(width: 12),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: colors.primary.withOpacity(0.2), height: 1),
          ),
        ),
        
        endDrawer: Drawer(
          backgroundColor: const Color(0xFF111111),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 20.0, top: 20.0, bottom: 10.0),
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, color: colors.primary),
                      const SizedBox(width: 12),
                      Text(
                        "SETTINGS MODULE",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colors.primary, letterSpacing: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    const SizedBox(height: 12),
                    Text("THEME COLOR ACCENTS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.4), letterSpacing: 1)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildColorButton(context, "Gold", const Color(0xFFD4AF37), const Color(0xFF252114)),
                        _buildColorButton(context, "Pink", const Color(0xFFFF2A85), const Color(0xFF2C131F)),
                        _buildColorButton(context, "Cyan", const Color(0xFF00E5FF), const Color(0xFF11282D)),
                        _buildColorButton(context, "Silver", const Color(0xFFE0E0E0), const Color(0xFF242424)),
                      ],
                    ),
                    const SizedBox(height: 24),

                    Text("GLOBAL ANIMATION SPEED (${_animationSpeedFactor.toStringAsFixed(1)}x)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.4), letterSpacing: 1)),
                    Slider(
                      min: 0.2,
                      max: 3.0,
                      divisions: 14,
                      activeColor: colors.primary,
                      value: _animationSpeedFactor,
                      onChanged: (val) => _updateAnimationSpeed(val),
                    ),
                    const SizedBox(height: 20),

                    Text("KEYBOARD SHORTCUTS & BINDS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.4), letterSpacing: 1)),
                    const SizedBox(height: 12),
                    ..._actionLabels.keys.map((action) {
                      final label = _actionLabels[action]!;
                      final key = _keybinds[action];
                      final isRebinding = _rebindingAction == action;
                      
                      String keyName = "Unbound";
                      if (key != null) {
                        keyName = key.keyLabel;
                      }
                      if (isRebinding) {
                        keyName = "Listening...";
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _rebindingAction = action;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isRebinding ? colors.primary.withOpacity(0.2) : const Color(0xFF161616),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isRebinding ? colors.primary : Colors.white10,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  keyName,
                                  style: TextStyle(
                                    fontSize: 11, 
                                    fontWeight: FontWeight.bold, 
                                    color: isRebinding ? colors.primary : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 24),

                    Text("TIMELINE VISUAL CUSTOMIZATION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.4), letterSpacing: 1)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text("Wave Line", style: TextStyle(fontSize: 12)),
                            selected: _isWaveForm,
                            selectedColor: colors.primaryContainer,
                            checkmarkColor: colors.primary,
                            onSelected: (val) => setState(() => _isWaveForm = true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text("Straight", style: TextStyle(fontSize: 12)),
                            selected: !_isWaveForm,
                            selectedColor: colors.primaryContainer,
                            checkmarkColor: colors.primary,
                            onSelected: (val) => setState(() => _isWaveForm = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text("Line Thickness (${_timelineThickness.toStringAsFixed(1)}px)", style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    Slider(
                      min: 1.0,
                      max: 8.0,
                      divisions: 7,
                      activeColor: colors.primary,
                      value: _timelineThickness,
                      onChanged: (val) => setState(() => _timelineThickness = val),
                    ),
                    const SizedBox(height: 20),

                    Text("MAIN DISPLAY MODE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.4), letterSpacing: 1)),
                    SwitchListTile(
                      title: const Text("Vinyl Record Player View", style: TextStyle(fontSize: 13, color: Colors.white)),
                      subtitle: const Text("Renders an interactive spinning vinyl turntable disc", style: TextStyle(fontSize: 10, color: Colors.white30)),
                      activeColor: colors.primary,
                      contentPadding: EdgeInsets.zero,
                      value: _isRecordPlayerMode,
                      onChanged: (val) => setState(() => _isRecordPlayerMode = val),
                    ),
                    
                    if (_isRecordPlayerMode) ...[
                      Text("Vinyl Spinning Speed (${_spinSpeedFactor.toStringAsFixed(1)}x)", style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      Slider(
                        min: 0.5,
                        max: 4.0,
                        divisions: 7,
                        activeColor: colors.primary,
                        value: _spinSpeedFactor,
                        onChanged: (val) => setState(() => _spinSpeedFactor = val),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 12),

                    Text("PLAYBACK ENGINE CONFIGS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.4), letterSpacing: 1)),
                    SwitchListTile(
                      title: const Text("Auto-Advance Queue", style: TextStyle(fontSize: 13, color: Colors.white)),
                      subtitle: const Text("Plays next available track automatically", style: TextStyle(fontSize: 10, color: Colors.white30)),
                      activeColor: colors.primary,
                      contentPadding: EdgeInsets.zero,
                      value: _autoAdvanceNext,
                      onChanged: (val) => setState(() => _autoAdvanceNext = val),
                    ),
                    if (_isWaveForm) ...[
                      Text("Wave Frequency Speed (${_waveSpeedFactor.toStringAsFixed(1)}x)", style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      Slider(
                        min: 0.5,
                        max: 2.0,
                        divisions: 3,
                        activeColor: colors.primary,
                        value: _waveSpeedFactor,
                        onChanged: (val) => setState(() => _waveSpeedFactor = val),
                      ),
                    ],
                    const SizedBox(height: 20),

                    Text("LIBRARY MANAGEMENT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.4), letterSpacing: 1)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF161616),
                        foregroundColor: Colors.white,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white10)),
                      ),
                      icon: Icon(Icons.cleaning_services_rounded, size: 16, color: colors.primary),
                      label: const Text("Wipe Memory Cache & Rescan", style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(context);
                        _clearCacheAndRescan();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        body: Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                child: KeyedSubtree(
                  key: ValueKey(_currentIndex),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0D0D),
                      image: _albumArtBytes != null
                          ? DecorationImage(
                              image: MemoryImage(_albumArtBytes!),
                              fit: BoxFit.cover,
                              opacity: 0.12, 
                            )
                          : null,
                    ),
                    child: _albumArtBytes == null
                        ? Center(
                            child: Container(
                              width: 400,
                              height: 400,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.primary.withOpacity(0.025),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
            
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                child: Container(color: Colors.transparent),
              ),
            ),

            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  width: _isQueueOpen ? 340 : 0, 
                  child: _isQueueOpen
                      ? Container(
                          color: const Color(0xFF111111).withOpacity(0.85), 
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                color: const Color(0xFF161616).withOpacity(0.5),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setState(() => _sidebarTab = 0),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          decoration: BoxDecoration(
                                            border: Border(bottom: BorderSide(color: _sidebarTab == 0 ? colors.primary : Colors.transparent, width: 2)),
                                          ),
                                          child: Text(
                                            "EXPLORER",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _sidebarTab == 0 ? colors.primary : Colors.white38, letterSpacing: 1),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setState(() => _sidebarTab = 1),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          decoration: BoxDecoration(
                                            border: Border(bottom: BorderSide(color: _sidebarTab == 1 ? colors.primary : Colors.transparent, width: 2)),
                                          ),
                                          child: Text(
                                            "ACTIVE QUEUE (${_flatTrackList.length})",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _sidebarTab == 1 ? colors.primary : Colors.white38, letterSpacing: 1),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              Expanded(
                                child: _sidebarTab == 0
                                    ? Column(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: TextField(
                                              controller: _searchController,
                                              onChanged: (val) => setState(() => _searchQuery = val),
                                              style: const TextStyle(fontSize: 13, color: Colors.white),
                                              decoration: InputDecoration(
                                                hintText: 'Search directories...',
                                                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                                                prefixIcon: Icon(Icons.search_rounded, color: colors.primary.withOpacity(0.5), size: 18),
                                                filled: true,
                                                fillColor: const Color(0xFF161616),
                                                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.05))),
                                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colors.primary.withOpacity(0.3))),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: filteredGroupedPlaylist.isEmpty
                                                ? Center(child: Text(_isScanning ? 'Mapping modules...' : 'No tracks match search', style: const TextStyle(color: Colors.white24, fontSize: 12)))
                                                : ListView(
                                                    children: filteredGroupedPlaylist.keys.map((String folderPath) {
                                                      final String customCleanName = _cleanFolderTitle(folderPath);
                                                      final List<File> tracksInFolder = filteredGroupedPlaylist[folderPath] ?? [];
                                                      return Theme(
                                                        data: theme.copyWith(dividerColor: Colors.transparent),
                                                        child: ExpansionTile(
                                                          initiallyExpanded: _searchQuery.isNotEmpty,
                                                          leading: const Icon(Icons.folder_rounded, color: Color(0xFFD4AF37), size: 20),
                                                          title: Text(customCleanName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                                                          children: tracksInFolder.map((File trackFile) {
                                                            final String trackName = trackFile.path.split('/').last;
                                                            final bool isCurrentlyPlaying = _currentIndex != -1 && _flatTrackList[_currentIndex].path == trackFile.path;
                                                            return Material(
                                                              color: isCurrentlyPlaying ? colors.primaryContainer : Colors.transparent,
                                                              child: ListTile(
                                                                contentPadding: const EdgeInsets.only(left: 40.0, right: 16.0),
                                                                leading: Icon(isCurrentlyPlaying ? Icons.play_circle_filled_rounded : Icons.music_note_outlined, color: isCurrentlyPlaying ? colors.primary : Colors.white30, size: 16),
                                                                title: Text(trackName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: isCurrentlyPlaying ? FontWeight.bold : FontWeight.normal, color: isCurrentlyPlaying ? colors.primary : Colors.white70)),
                                                                onTap: () => _selectTrackDirectly(trackFile),
                                                              ),
                                                            );
                                                          }).toList(),
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                          ),
                                        ],
                                      )
                                    : ReorderableListView.builder(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        itemCount: _flatTrackList.length,
                                        onReorder: (int oldIndex, int newIndex) {
                                          setState(() {
                                            if (oldIndex < newIndex) {
                                              newIndex -= 1;
                                            }
                                            final File item = _flatTrackList.removeAt(oldIndex);
                                            _flatTrackList.insert(newIndex, item);
                                            
                                            if (_currentIndex == oldIndex) {
                                              _currentIndex = newIndex;
                                            } else if (_currentIndex > oldIndex && _currentIndex <= newIndex) {
                                              _currentIndex -= 1;
                                            } else if (_currentIndex < oldIndex && _currentIndex >= newIndex) {
                                              _currentIndex += 1;
                                            }
                                            _generateShuffleSequence();
                                          });
                                        },
                                        itemBuilder: (context, idx) {
                                          final File fileItem = _flatTrackList[idx];
                                          final String name = fileItem.path.split('/').last;
                                          final bool isCurrent = idx == _currentIndex;
                                          return Material(
                                            key: ValueKey(fileItem.path),
                                            color: isCurrent ? colors.primaryContainer : Colors.transparent,
                                            child: ListTile(
                                              leading: CircleAvatar(
                                                radius: 11,
                                                backgroundColor: isCurrent ? colors.primary : Colors.white10,
                                                child: Text("${idx + 1}", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isCurrent ? Colors.black : Colors.white60)),
                                              ),
                                              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: isCurrent ? colors.primary : Colors.white.withOpacity(0.8), fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                                              trailing: const Icon(Icons.drag_handle_rounded, size: 16, color: Colors.white24),
                                              onTap: () => _loadTrack(idx),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                if (_isQueueOpen) VerticalDivider(width: 1, color: colors.primary.withOpacity(0.15)),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48.0, vertical: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        mainDeck,
                        const SizedBox(height: 16),

                        RepaintBoundary(
                          child: CustomPaint(
                            size: const Size(360, 32),
                            painter: MicroSpectrumVisualizerPainter(
                              animation: _visualizerController,
                              isPlaying: _isPlaying,
                              barColor: colors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        Text(
                          _currentTrackName,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              icon: Icon(Icons.pin_drop_rounded, size: 14, color: _loopA != null ? Colors.greenAccent : Colors.white38),
                              label: Text(
                                _loopA == null ? "Set Loop [A]" : "A: ${_formatDuration(_loopA!)}",
                                style: TextStyle(fontSize: 11, color: _loopA != null ? Colors.greenAccent : Colors.white70),
                              ),
                              onPressed: _setLoopA,
                            ),
                            const SizedBox(width: 16),
                            TextButton.icon(
                              icon: Icon(Icons.pin_drop_rounded, size: 14, color: _loopB != null ? Colors.redAccent : Colors.white38),
                              label: Text(
                                _loopB == null ? "Set Loop [B]" : "B: ${_formatDuration(_loopB!)}",
                                style: TextStyle(fontSize: 11, color: _loopB != null ? Colors.redAccent : Colors.white70),
                              ),
                              onPressed: _setLoopB,
                            ),
                            const SizedBox(width: 16),
                            if (_loopA != null && _loopB != null) ...[
                              IconButton(
                                icon: Icon(
                                  _isABLoopActive ? Icons.loop_rounded : Icons.play_disabled_rounded, 
                                  size: 16, 
                                  color: _isABLoopActive ? colors.primary : Colors.white38,
                                ),
                                tooltip: _isABLoopActive ? "Pause Loop" : "Activate Loop",
                                onPressed: () => setState(() => _isABLoopActive = !_isABLoopActive),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (_loopA != null || _loopB != null)
                              IconButton(
                                icon: const Icon(Icons.layers_clear_rounded, size: 16, color: Colors.white54),
                                tooltip: "Clear Loop Points",
                                onPressed: _clearABLoop,
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        Column(
                          children: [
                            LayoutBuilder(
                              builder: (context, constraints) {
                                return GestureDetector(
                                  onHorizontalDragUpdate: (details) => _handleWaveScrub(details.localPosition, constraints.maxWidth),
                                  onTapDown: (details) => _handleWaveScrub(details.localPosition, constraints.maxWidth),
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      size: Size(constraints.maxWidth, 50),
                                      painter: AudioWaveformPainter(
                                        progress: progressRatio,
                                        isTrackingActive: _isPlaying && _flatTrackList.isNotEmpty,
                                        waveColor: colors.primary,
                                        isWaveMode: _isWaveForm,
                                        thickness: _timelineThickness,
                                        animation: _waveAnimationController,
                                        loopARatio: loopARatio,
                                        loopBRatio: loopBRatio,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_formatDuration(_position), style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                                  Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(width: 140),
                            const Spacer(),

                            IconButton(
                              icon: Icon(_isShuffleOn ? Icons.shuffle_on_rounded : Icons.shuffle_rounded),
                              color: _isShuffleOn ? colors.primary : Colors.white38,
                              iconSize: 22,
                              onPressed: _toggleShuffle,
                              tooltip: 'Shuffle Mode',
                            ),
                            const SizedBox(width: 24),
                            IconButton(
                              iconSize: 34,
                              icon: const Icon(Icons.skip_previous_rounded),
                              color: _flatTrackList.isNotEmpty ? colors.primary : Colors.white24,
                              onPressed: _flatTrackList.isNotEmpty ? _skipBackward : null,
                            ),
                            const SizedBox(width: 20),
                            IconButton.filled(
                              iconSize: 52,
                              style: IconButton.styleFrom(backgroundColor: colors.primary, foregroundColor: Colors.black),
                              icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                              onPressed: _flatTrackList.isNotEmpty ? _togglePlayPause : null,
                            ),
                            const SizedBox(width: 20),
                            IconButton(
                              iconSize: 34,
                              icon: const Icon(Icons.skip_next_rounded),
                              color: _flatTrackList.isNotEmpty ? colors.primary : Colors.white24,
                              onPressed: _flatTrackList.isNotEmpty ? _skipForward : null,
                            ),
                            const SizedBox(width: 24),
                            IconButton(
                              icon: Icon(_isLoopOn ? Icons.repeat_one_on_rounded : Icons.repeat_rounded),
                              color: _isLoopOn ? colors.primary : Colors.white38,
                              iconSize: 22,
                              onPressed: () => setState(() => _isLoopOn = !_isLoopOn),
                              tooltip: 'Repeat Track',
                            ),

                            const Spacer(),

                            SizedBox(
                              width: 140,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: Icon(_showLyrics ? Icons.subtitles_rounded : Icons.subtitles_off_rounded),
                                    color: _showLyrics ? colors.primary : Colors.white38,
                                    iconSize: 20,
                                    onPressed: () {
                                      setState(() {
                                        _showLyrics = !_showLyrics;
                                        if (_showLyrics) {
                                          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActiveLyric());
                                        }
                                      });
                                    },
                                    tooltip: 'Toggle Scrolling Synced Lyrics',
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    _volume == 0.0 
                                        ? Icons.volume_off_rounded 
                                        : _volume < 0.4 
                                            ? Icons.volume_down_rounded 
                                            : Icons.volume_up_rounded,
                                    size: 16,
                                    color: Colors.white54,
                                  ),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 2.5,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                      ),
                                      child: Slider(
                                        value: _volume,
                                        activeColor: colors.primary,
                                        inactiveColor: Colors.white10,
                                        onChanged: (val) {
                                          setState(() {
                                            _volume = val;
                                          });
                                          _audioPlayer.setVolume(val);
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorButton(BuildContext context, String label, Color mainColor, Color containerColor) {
    bool isSelected = Theme.of(context).colorScheme.primary.value == mainColor.value;
    return GestureDetector(
      onTap: () => widget.onThemeChanged(mainColor, containerColor),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: mainColor,
          shape: BoxShape.circle,
          border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 2.5),
        ),
        child: isSelected ? const Icon(Icons.check_rounded, color: Colors.black, size: 18) : null,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// MICRO-SPECTRUM EQUALIZER FREQUENCY VISUALIZER GRAPHICS PAINTER
// -----------------------------------------------------------------------------
class MicroSpectrumVisualizerPainter extends CustomPainter {
  final Animation<double> animation;
  final bool isPlaying;
  final Color barColor;

  MicroSpectrumVisualizerPainter({
    required this.animation,
    required this.isPlaying,
    required this.barColor,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final int barCount = 28;
    final double spacing = 3.5;
    final double totalSpacing = spacing * (barCount - 1);
    final double barWidth = (size.width - totalSpacing) / barCount;
    
    final Paint paint = Paint()..style = PaintingStyle.fill;

    final double smoothAnim = Curves.easeInOutSine.transform(animation.value);

    for (int i = 0; i < barCount; i++) {
      double factor = 0.15; 

      if (isPlaying) {
        final double phase1 = sin((smoothAnim * 2 * pi) + (i * 0.4));
        final double phase2 = cos((smoothAnim * 4 * pi) - (i * 0.9));
        factor = ((phase1 * 0.45) + (phase2 * 0.35)).abs().clamp(0.12, 1.0);
        
        if (i < 6) factor *= 1.15; 
        if (i > 22) factor *= 0.85; 
      } else {
        factor = 0.12 + (sin((smoothAnim * pi) + (i * 0.2)).abs() * 0.05);
      }

      final double currentBarHeight = size.height * factor;
      final double xPos = i * (barWidth + spacing);
      final double yPos = size.height - currentBarHeight;

      paint.color = barColor.withOpacity(0.3 + (factor * 0.7));

      final RRect roundedBar = RRect.fromRectAndRadius(
        Rect.fromLTWH(xPos, yPos, barWidth, currentBarHeight),
        const Radius.circular(2.0),
      );
      canvas.drawRRect(roundedBar, paint);
    }
  }

  @override
  bool shouldRepaint(covariant MicroSpectrumVisualizerPainter oldDelegate) => true;
}

// -----------------------------------------------------------------------------
// ISOLATED DECK SUB-MODULE (AnimationController driven ticker loop)
// -----------------------------------------------------------------------------
class IsolatedVinylDeck extends StatefulWidget {
  final bool isPlaying;
  final double spinSpeedFactor;
  final ui.Image? decodedImage;
  final Color primaryColor;

  const IsolatedVinylDeck({
    super.key,
    required this.isPlaying,
    required this.spinSpeedFactor,
    this.decodedImage,
    required this.primaryColor,
  });

  @override
  State<IsolatedVinylDeck> createState() => _IsolatedVinylDeckState();
}

class _IsolatedVinylDeckState extends State<IsolatedVinylDeck> with TickerProviderStateMixin {
  late AnimationController _spinController;
  late AnimationController _particleController;
  late final ParticleChangeNotifier _particleNotifier;

  @override
  void initState() {
    super.initState();
    _particleNotifier = ParticleChangeNotifier(widget.spinSpeedFactor);
    _spinController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (3000 / widget.spinSpeedFactor).toInt()),
    );

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _particleController.addListener(() {
      if (mounted) {
        _particleNotifier.tick(widget.isPlaying);
      }
    });

    if (widget.isPlaying) {
      _spinController.repeat();
    }
  }

  @override
  void didUpdateWidget(IsolatedVinylDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinSpeedFactor != oldWidget.spinSpeedFactor || widget.isPlaying != oldWidget.isPlaying) {
      _particleNotifier.speedFactor = widget.spinSpeedFactor;
      _spinController.duration = Duration(milliseconds: (3000 / widget.spinSpeedFactor).toInt());
      if (widget.isPlaying) {
        _spinController.repeat();
      } else {
        _spinController.stop();
      }
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    _particleController.dispose();
    _particleNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 290,
      height: 290,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: ParticleBackgroundPainter(
                  notifier: _particleNotifier,
                  particleColor: widget.primaryColor,
                ),
              ),
            ),
          ),
          RotationTransition(
            turns: _spinController,
            child: CustomPaint(
              size: const Size(250, 250),
              painter: VinylRecordPainter(decodedImage: widget.decodedImage),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            bottom: 10,
            left: 10,
            child: IgnorePointer(
              child: Container(
                alignment: Alignment.topRight,
                child: AnimatedTonearm(isPlaying: widget.isPlaying),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PARTICLE PERFORMANCE ENGINE (BASED ON CHANGENOTIFIER LOGIC)
// -----------------------------------------------------------------------------
class ParticleChangeNotifier extends ChangeNotifier {
  double speedFactor;
  final List<_NoteParticleData> activeParticles = [];
  final Random _rand = Random();

  ParticleChangeNotifier(this.speedFactor);

  void tick(bool isPlaying) {
    for (int i = activeParticles.length - 1; i >= 0; i--) {
      final p = activeParticles[i];
      p.offsetX += p.velocityX;
      p.offsetY += p.velocityY;
      p.opacity -= 0.018; 
      p.scale *= 0.985;   
      if (p.opacity <= 0.0 || p.scale <= 0.1) {
        activeParticles.removeAt(i);
      }
    }

    if (isPlaying && _rand.nextDouble() < (0.05 * speedFactor + 0.03)) {
      double angle = _rand.nextDouble() * 2 * pi;
      double startRadius = 35.0; 
      activeParticles.add(
        _NoteParticleData(
          offsetX: cos(angle) * startRadius,
          offsetY: sin(angle) * startRadius,
          velocityX: cos(angle) * (_rand.nextDouble() * 1.8 + 0.6) * (speedFactor * 0.7 + 0.3), 
          velocityY: sin(angle) * (_rand.nextDouble() * 1.8 + 0.6) * (speedFactor * 0.7 + 0.3),
          opacity: 1.0,
          scale: _rand.nextDouble() * 0.4 + 0.6,
          isAltShape: _rand.nextBool(),
        ),
      );
    }
    notifyListeners();
  }
}

class ParticleBackgroundPainter extends CustomPainter {
  final ParticleChangeNotifier notifier;
  final Color particleColor;

  ParticleBackgroundPainter({required this.notifier, required this.particleColor}) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    final double center = size.width / 2;
    final Offset centerOffset = Offset(center, center);

    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (var p in notifier.activeParticles) {
      paint.color = particleColor.withOpacity(p.opacity);
      final double x = centerOffset.dx + p.offsetX;
      final double y = centerOffset.dy + p.offsetY;
      
      if (p.isAltShape) {
        canvas.drawCircle(Offset(x, y), 5.5 * p.scale, paint);
      } else {
        canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: 9 * p.scale, height: 9 * p.scale), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ParticleBackgroundPainter oldDelegate) => true;
}

// -----------------------------------------------------------------------------
// TONEARM AND HEADSHELL SYSTEM ENGINE (CUSTOM PAINTER)
// -----------------------------------------------------------------------------
class AnimatedTonearm extends StatelessWidget {
  final bool isPlaying;

  const AnimatedTonearm({super.key, required this.isPlaying});

  @override
  Widget build(BuildContext context) {
    final double targetAngle = isPlaying ? 0.32 : -0.12;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: -0.12, end: targetAngle),
      duration: const Duration(milliseconds: 750),
      curve: Curves.easeInOutCubic, 
      builder: (context, angle, child) {
        return Transform.rotate(
          angle: angle,
          alignment: Alignment.topRight, 
          child: CustomPaint(
            size: const Size(100, 240),
            painter: TonearmPainter(),
          ),
        );
      },
    );
  }
}

class TonearmPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..isAntiAlias = true; 
    final Offset pivot = Offset(size.width - 20, 20);

    paint.color = const Color(0xFF1F1F1F);
    canvas.drawCircle(pivot, 18, paint);
    paint.color = const Color(0xFF3A3A3A);
    canvas.drawCircle(pivot, 12, paint);
    paint.color = const Color(0xFFD4AF37); 
    canvas.drawCircle(pivot, 5, paint);

    final Path armPath = Path();
    armPath.moveTo(pivot.dx, pivot.dy);
    armPath.cubicTo(
      pivot.dx - 12, pivot.dy + 55,
      pivot.dx + 18, pivot.dy + 125,
      size.width / 2, size.height - 35,
    );

    paint.color = const Color(0xFFCCCCCC); 
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 3.5;
    paint.strokeCap = StrokeCap.round;
    canvas.drawPath(armPath, paint);

    final Offset armEnd = Offset(size.width / 2, size.height - 35);
    
    canvas.save();
    canvas.translate(armEnd.dx, armEnd.dy);
    canvas.rotate(-0.22); 

    paint.style = PaintingStyle.fill;
    paint.color = const Color(0xFF1A1A1A);
    final Rect headshellRect = Rect.fromCenter(center: const Offset(0, 10), width: 14, height: 24);
    canvas.drawRRect(RRect.fromRectAndRadius(headshellRect, const Radius.circular(3)), paint);

    paint.color = const Color(0xFFD4AF37);
    final Path liftHandle = Path()
      ..moveTo(7, 4)
      ..quadraticBezierTo(13, 2, 15, -4);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.8;
    canvas.drawPath(liftHandle, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// VINYL DISC RECORD COMPONENT PAINTER
// -----------------------------------------------------------------------------
class VinylRecordPainter extends CustomPainter {
  final ui.Image? decodedImage;
  VinylRecordPainter({this.decodedImage});

  @override
  void paint(Canvas canvas, Size size) {
    final double center = size.width / 2;
    final Offset centerOffset = Offset(center, center);
    final double radius = size.width / 2;

    final Paint vinylBodyPaint = Paint()
      ..color = const Color(0xFF141414)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(centerOffset, radius, vinylBodyPaint);

    final Paint groovePaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (double i = radius - 15; i > 40; i -= 12) {
      canvas.drawCircle(centerOffset, i, groovePaint);
    }

    final double labelRadius = 42.0;
    
    canvas.save();
    final Path circleClipPath = Path()..addOval(Rect.fromCircle(center: centerOffset, radius: labelRadius));
    canvas.clipPath(circleClipPath);

    if (decodedImage != null) {
      final srcRect = Rect.fromLTWH(0, 0, decodedImage!.width.toDouble(), decodedImage!.height.toDouble());
      final dstRect = Rect.fromCircle(center: centerOffset, radius: labelRadius);
      canvas.drawImageRect(decodedImage!, srcRect, dstRect, Paint()..isAntiAlias = true..filterQuality = ui.FilterQuality.medium);
    } else {
      final Paint labelBackgroundPaint = Paint()
        ..color = const Color(0xFF222222)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(centerOffset, labelRadius, labelBackgroundPaint);

      final Paint innerAccentRim = Paint()
        ..color = const Color(0xFFD4AF37).withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(centerOffset, labelRadius - 4, innerAccentRim);
    }
    canvas.restore();

    canvas.drawCircle(centerOffset, 5.0, Paint()..color = const Color(0xFF0D0D0D)..style = PaintingStyle.fill);
    canvas.drawCircle(centerOffset, 1.8, Paint()..color = Colors.white30..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant VinylRecordPainter oldDelegate) {
    return oldDelegate.decodedImage != decodedImage;
  }
}

// -----------------------------------------------------------------------------
// SCROLLABLE TIMELINE GRAPHIC PAINTER
// -----------------------------------------------------------------------------
class AudioWaveformPainter extends CustomPainter {
  final double progress;
  final bool isTrackingActive;
  final Color waveColor;
  final bool isWaveMode;
  final double thickness;
  final AnimationController animation; 
  final double? loopARatio;
  final double? loopBRatio;

  AudioWaveformPainter({
    required this.progress,
    required this.isTrackingActive,
    required this.waveColor,
    required this.isWaveMode,
    required this.thickness,
    required this.animation,
    this.loopARatio,
    this.loopBRatio,
  }) : super(repaint: animation); 

  @override
  void paint(Canvas canvas, Size size) {
    final double midY = size.height / 2;
    final double width = size.width;
    
    final double wavePhase = isWaveMode ? (animation.value * 2 * pi) : 0.0;
    final double amplitude = isWaveMode ? (isTrackingActive ? 14.0 : 3.0) : 0.0; 
    final double frequency = isTrackingActive ? 0.04 : 0.02;

    final Path playedWavePath = Path();
    final Path unplayedWavePath = Path();
    double splitX = width * progress;

    final Paint progressPaint = Paint()
      ..color = waveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    final Paint backgroundPaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, thickness - 1.0)
      ..strokeCap = StrokeCap.round;

    for (double x = 0; x <= width; x += 2) { 
      double y = midY;
      if (isWaveMode) {
        y = midY + sin((x * frequency) + wavePhase) * amplitude;
      }

      if (x == 0) {
        playedWavePath.moveTo(x, y);
        unplayedWavePath.moveTo(x, y);
      } else {
        if (x <= splitX) {
          playedWavePath.lineTo(x, y);
          unplayedWavePath.moveTo(x, y); 
        } else {
          unplayedWavePath.lineTo(x, y);
        }
      }
    }

    canvas.drawPath(unplayedWavePath, backgroundPaint);
    canvas.drawPath(playedWavePath, progressPaint);

    if (loopARatio != null) {
      final double x = width * loopARatio!;
      final Paint paintA = Paint()
        ..color = Colors.greenAccent.withOpacity(0.85)
        ..strokeWidth = 2.0;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintA);
      
      final textPainter = TextPainter(
        text: const TextSpan(text: 'A', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(x + 3, 2));
    }

    if (loopBRatio != null) {
      final double x = width * loopBRatio!;
      final Paint paintB = Paint()
        ..color = Colors.redAccent.withOpacity(0.85)
        ..strokeWidth = 2.0;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintB);

      final textPainter = TextPainter(
        text: const TextSpan(text: 'B', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(x + 3, 2));
    }

    if (splitX > 0 && splitX < width) {
      double thumbY = midY;
      if (isWaveMode) {
        thumbY = midY + sin((splitX * frequency) + wavePhase) * amplitude;
      }
      canvas.drawCircle(Offset(splitX, thumbY), thickness + 2.0, Paint()..color = waveColor..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant AudioWaveformPainter oldDelegate) => true;
}

class LyricLine {
  final Duration timestamp;
  final String text;

  LyricLine({required this.timestamp, required this.text});
}

class _NoteParticleData {
  double offsetX;
  double offsetY;
  double velocityX;
  double velocityY;
  double opacity;
  double scale;
  final bool isAltShape;

  _NoteParticleData({
    required this.offsetX,
    required this.offsetY,
    required this.velocityX,
    required this.velocityY,
    required this.opacity,
    required this.scale,
    required this.isAltShape,
  });
}

// -----------------------------------------------------------------------------
// PLACEHOLDER SERVICE STUBS (Remove/Replace if defined in external files)
// -----------------------------------------------------------------------------
class StorageService {
  static Future<void> init() async {
    debugPrint("StorageService initialized.");
  }
}

class MetadataService {
  static Future<void> scanMusic() async {
    debugPrint("Metadata database scan triggered.");
  }
}

class ThemeService {
  static Future<Map<String, Color>> generateColorsFromImage(Uint8List imageBytes) async {
    try {
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        MemoryImage(imageBytes),
        maximumColorCount: 8,
      );
      final Color major = paletteGenerator.dominantColor?.color ?? const Color(0xFFD4AF37);
      final Color container = major.withOpacity(0.15);
      return {
        'primary': major,
        'container': container,
      };
    } catch (e) {
      debugPrint("Palette theme extraction fallback: $e");
      return {
        'primary': const Color(0xFFD4AF37),
        'container': const Color(0xFF252114),
      };
    }
  }
}