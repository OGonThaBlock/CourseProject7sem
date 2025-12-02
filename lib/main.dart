import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final pages = [
    MetronomePage(),
    MenuPage(),
    TunerPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.timer),
            label: 'Метроном',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: 'Меню',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tune),
            label: 'Тюнер',
          ),
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
  int beatCount = 4; // размер 4/4
  int currentBeat = 1;

  @override
  void initState() {
    super.initState();
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

//////////////////////////////////////////////////////////////////
// СТРАНИЦА МЕНЮ (2-я вкладка)
//////////////////////////////////////////////////////////////////

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Меню")),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.music_note),
            title: const Text("Аккорды"),
            onTap: () {}, // заглушка
          ),
          ListTile(
            leading: const Icon(Icons.school),
            title: const Text("Теория"),
            onTap: () {}, // заглушка
          ),
        ],
      ),
    );
  }
}

//виджет тюнера
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Тюнер")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _frequency > 0 ? '${_frequency.toStringAsFixed(1)} Hz' : '–',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text(_status),
            const SizedBox(height: 40),
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
              setState(() {
                _frequency = freq;
                _status = "Слушаю...";
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
      _status = "Остановлено";
    });
  }
}
