import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/theory_api_service.dart';

const List<String> noteNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F',
  'F#', 'G', 'G#', 'A', 'A#', 'B'
];

class NoteResult {
  final String note;
  final int octave;
  final double cents;

  NoteResult(this.note, this.octave, this.cents);
}

NoteResult frequencyToNote(double frequency) {
  final double noteNumber =
      69 + 12 * (log(frequency / 440.0) / ln2);

  final int nearestNote = noteNumber.round();
  final double cents = (noteNumber - nearestNote) * 100;

  final String note = noteNames[nearestNote % 12];
  final int octave = (nearestNote ~/ 12) - 1;

  return NoteResult(note, octave, cents);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('is_dark_theme') ?? false;
    if (mounted) {
      setState(() {
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      });
    }
  }

  Future<void> _toggleTheme(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_theme', isDark);
    if (mounted) {
      setState(() {
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: _themeMode,
      home: HomePage(toggleTheme: _toggleTheme),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  final Future<void> Function(bool) toggleTheme;

  const HomePage({super.key, required this.toggleTheme});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  List<Widget> get pages => [
    MenuPage(),
    MetronomePage(),
    TunerPage(),
    SettingsPage(toggleTheme: widget.toggleTheme),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        unselectedItemColor: Colors.grey[600],
        selectedItemColor: Colors.green,
        backgroundColor: Theme.of(context).bottomNavigationBarTheme.backgroundColor,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Меню'),
          BottomNavigationBarItem(icon: Icon(Icons.timer), label: 'Метроном'),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: 'Тюнер'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Настройки'),
        ],
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

//////////////////////////////////////////////////////////////////
/// СТРАНИЦА МЕТРОНОМА
//////////////////////////////////////////////////////////////////
class MetronomePage extends StatefulWidget {
  @override
  State<MetronomePage> createState() => _MetronomePageState();
}

class _MetronomePageState extends State<MetronomePage> {
  final playerAccent = AudioPlayer();
  final playerTick = AudioPlayer();

  Timer? timer;
  int bpm = 120;
  int beatCount = 4;
  int currentBeat = 1;

  @override
  void initState() {
    super.initState();
    AnalyticsService.incrementMetronome();
    _loadSounds();
  }

  Future<void> _loadSounds() async {
    await playerAccent.setAsset('assets/tick_accent.wav');
    await playerTick.setAsset('assets/tick.wav');
  }

  void startMetronome() {
    stopMetronome();

    final interval = Duration(milliseconds: (60000 / bpm).round());

    timer = Timer.periodic(interval, (timer) {
      if (currentBeat == 1) {
        playerAccent.seek(Duration.zero);
        playerAccent.play();
      } else {
        playerTick.seek(Duration.zero);
        playerTick.play();
      }

      setState(() {
        currentBeat++;
        if (currentBeat > beatCount) currentBeat = 1;
      });
    });
  }

  void stopMetronome() {
    timer?.cancel();
    timer = null;
    currentBeat = 1;
    setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    playerAccent.dispose();
    playerTick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Метроном")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text("BPM: $bpm", style: const TextStyle(fontSize: 24)),
            Slider(
              value: bpm.toDouble(),
              min: 40,
              max: 240,
              onChanged: (v) => setState(() => bpm = v.round()),
            ),

            const SizedBox(height: 30),

            Text("Размер: $beatCount/4", style: const TextStyle(fontSize: 24)),
            Slider(
              value: beatCount.toDouble(),
              min: 2,
              max: 8,
              divisions: 6,
              label: beatCount.toString(),
              onChanged: (v) => setState(() => beatCount = v.round()),
            ),

            const SizedBox(height: 40),

            Text("Текущая доля: $currentBeat",
                style: const TextStyle(fontSize: 32)),

            const SizedBox(height: 60),

            ElevatedButton(
              onPressed: timer == null ? startMetronome : stopMetronome,
              child: Text(timer == null ? "Старт" : "Стоп"),
            ),
          ],
        ),
      ),
    );
  }
}

const String chordsHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <script async type="text/javascript"
    src="https://www.scales-chords.com/api/scales-chords-api.js"></script>
</head>
<body style="background-color:white; text-align:center;">

  <h3>C major</h3>
  <ins class="scales_chords_api"
       chord="C"
       instrument="guitar"
       output="image"
       width="150px"
       height="200px"
       nolink="true"></ins>

  <h3>Am</h3>
  <ins class="scales_chords_api"
       chord="Am"
       instrument="guitar"
       output="image"
       width="150px"
       height="200px"
       nolink="true"></ins>

</body>
</html>
''';
//////////////////////////////////////////////////////////////////
// СТРАНИЦА МЕНЮ (2-я вкладка)
//////////////////////////////////////////////////////////////////
/*
class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Аккорды")),
      body: WebViewWidget(
        controller: WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadHtmlString(chordsHtml),
      ),
    );
  }
}
*/
class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.incrementMenu();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Меню")),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.music_note),
            title: const Text("Аккорды"),
            onTap: () {
              AnalyticsService.incrementChords();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChordsPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.school),
            title: const Text("Теория"),
            onTap: () {
              AnalyticsService.incrementTheory();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TheoryPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ChordsPage extends StatelessWidget {
  const ChordsPage({super.key});

  final List<String> chords = const [
    'C',
    'Cm',
    'D',
    'Dm',
    'E',
    'Em',
    'F',
    'Fm',
    'G',
    'Gm',
    'A',
    'Am',
    'B',
    'Bm',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Аккорды")),
      body: ListView.builder(
        itemCount: chords.length,
        itemBuilder: (context, index) {
          final chord = chords[index];
          return ListTile(
            leading: const Icon(Icons.queue_music),
            title: Text(chord),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChordViewPage(chord: chord),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ChordViewPage extends StatelessWidget {
  final String chord;
  const ChordViewPage({super.key, required this.chord});

  @override
  Widget build(BuildContext context) {
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <script async src="https://www.scales-chords.com/api/scales-chords-api.js"></script>
</head>
<body style="text-align:center;">
  <h2>$chord</h2>
  <ins class="scales_chords_api"
       chord="$chord"
       instrument="guitar"
       output="image"
       width="300px"
       height="240px"
       nolink="true"></ins>
</body>
</html>
''';

    return Scaffold(
      appBar: AppBar(title: Text('Аккорд $chord')),
      body: WebViewWidget(
        controller: WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadHtmlString(html),
      ),
    );
  }
}

class TheoryPage extends StatefulWidget {
  const TheoryPage({super.key});

  @override
  State<TheoryPage> createState() => _TheoryPageState();
}

class _TheoryPageState extends State<TheoryPage> {
  TheoryData? _theoryData;
  bool _isLoading = true;
  bool _useLocal = false;

  @override
  void initState() {
    super.initState();
    _loadTheory();
  }

  Future<void> _loadTheory() async {
    setState(() {
      _isLoading = true;
      _useLocal = false;
    });

    // Пытаемся загрузить с API
    final remoteData = await TheoryApiService.fetchTheoryFromApi();

    if (remoteData != null) {
      setState(() {
        _theoryData = remoteData;
        _isLoading = false;
      });
    } else {
      // Если не удалось — используем локальные данные
      setState(() {
        _theoryData = TheoryApiService.getLocalFallback();
        _useLocal = true;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text("Теория")),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final data = _theoryData!;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Теория"),
        actions: [
          if (_useLocal)
            const Tooltip(
              message: "Используются локальные данные (нет соединения с сервером)",
              child: Icon(Icons.cloud_off, color: Colors.orange),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            for (var section in data.sections)
              _buildSection(section.heading, section.content),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(content, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
      ],
    );
  }
}
//////////////////////////////////////////////////////////////////
//виджет тюнера
//////////////////////////////////////////////////////////////////
class TunerPage extends StatefulWidget {
  const TunerPage({super.key});

  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
  static const platform = MethodChannel('com.example.kursproj/pitch');
  double _frequency = 0.0;
  bool _isListening = false;
  String _status = "Нажмите «Старт», чтобы начать";
  String _note = '–';
  int _octave = 0;
  double _cents = 0.0;

  @override
  void initState() {
    super.initState();
    AnalyticsService.incrementTuner();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Тюнер")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$_note$_octave',
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              _frequency > 0 ? '${_frequency.toStringAsFixed(1)} Hz' : '–',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 40),
            _TuningScale(cents: _cents),
            const SizedBox(height: 40),
            Text(_status),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isListening ? _stopListening : _startListening,
              child: Text(_isListening ? "Стоп" : "Старт"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startListening() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _status = "Разрешение на микрофон отклонено";
        });
      }
      return;
    }

    try {
      await platform.invokeMethod('startPitchDetection');
      if (mounted) {
        platform.setMethodCallHandler((call) async {
          if (call.method == 'onFrequencyUpdate') {
            final freq = call.arguments['frequency'] as double?;
            if (freq != null && mounted) {
              final noteResult = frequencyToNote(freq);

              setState(() {
                _frequency = freq;
                _note = noteResult.note;
                _octave = noteResult.octave;
                _cents = noteResult.cents.clamp(-50.0, 50.0);
                _status = "";
              });
            }
          }
        });
        setState(() {
          _isListening = true;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _status = "Ошибка: ${e.message}";
        });
      }
    }
  }

  Future<void> _stopListening() async {
    platform.invokeMethod('stopPitchDetection');
    setState(() {
      _isListening = false;
      _frequency = 0.0;
      _status = "";
    });
  }
}

class _TuningScale extends StatelessWidget {
  final double cents;

  const _TuningScale({required this.cents});

  @override
  Widget build(BuildContext context) {
    Color color;
    final abs = cents.abs();

    if (abs < 5) {
      color = Colors.green;
    } else if (abs < 15) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Column(
      children: [
        Container(
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: Colors.grey.shade300,
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 2,
                  color: Colors.black,
                ),
              ),
              Align(
                alignment: Alignment((cents / 50).clamp(-1.0, 1.0), 0),
                child: Container(
                  width: 6,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        Text(
          '${cents.toStringAsFixed(1)} cents',
          style: TextStyle(color: color),
        ),
      ],
    );
  }
}

class AnalyticsService {
  static const String _keyMetronome = 'visits_metronome';
  static const String _keyTuner = 'visits_tuner';
  static const String _keyMenu = 'visits_menu';
  static const String _keyChords = 'visits_chords';
  static const String _keyTheory = 'visits_theory';
  static const String _keySettings = 'visits_settings';

  static Future<void> increment(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + 1);
  }

  static Future<Map<String, int>> getVisits() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Метроном': prefs.getInt(_keyMetronome) ?? 0,
      'Тюнер': prefs.getInt(_keyTuner) ?? 0,
      'Меню': prefs.getInt(_keyMenu) ?? 0,
      'Аккорды': prefs.getInt(_keyChords) ?? 0,
      'Теория': prefs.getInt(_keyTheory) ?? 0,
      'Настройки': prefs.getInt(_keySettings) ?? 0,
    };
  }

  static Future<void> incrementMetronome() => increment(_keyMetronome);
  static Future<void> incrementTuner() => increment(_keyTuner);
  static Future<void> incrementMenu() => increment(_keyMenu);
  static Future<void> incrementChords() => increment(_keyChords);
  static Future<void> incrementTheory() => increment(_keyTheory);
  static Future<void> incrementSettings() => increment(_keySettings);
}


class SettingsPage extends StatefulWidget {
  final Future<void> Function(bool) toggleTheme;

  const SettingsPage({super.key, required this.toggleTheme});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isDarkTheme = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentTheme();
    AnalyticsService.incrementSettings();
  }

  Future<void> _loadCurrentTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('is_dark_theme') ?? false;
    if (mounted) {
      setState(() {
        _isDarkTheme = isDark;
      });
    }
  }

  Future<void> _onToggle(bool value) async {
    await widget.toggleTheme(value); // вызываем callback из MyApp
    if (mounted) {
      setState(() {
        _isDarkTheme = value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Настройки")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Тема приложения",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Тёмная тема"),
                Switch(
                  value: _isDarkTheme,
                  onChanged: _onToggle,
                  activeColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const Divider(height: 32),
            const Text(
              "Статистика использования",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, int>>(
              future: AnalyticsService.getVisits(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Column(
                    children: [
                      for (final entry in snapshot.data!.entries)
                        ListTile(
                          title: Text(entry.key),
                          trailing: Text('${entry.value} раз(а)'),
                        ),
                    ],
                  );
                } else {
                  return const Text("Загрузка...");
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.book),
              title: const Text("Посмотреть документацию"),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DocumentationPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class DocumentationPage extends StatefulWidget {
  @override
  State<DocumentationPage> createState() => _DocumentationPageState();
}

class _DocumentationPageState extends State<DocumentationPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadRequest(Uri.parse('https://ogonthablock.github.io/CourseProject7sem/#/'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Документация'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}