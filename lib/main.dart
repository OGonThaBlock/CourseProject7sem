import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/theory_api_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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

  //настукивание
  List<int> _tapTimes = [];
  static const int _maxTaps = 5;

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

  void _handleTapTempo() {
    final now = DateTime.now().millisecondsSinceEpoch;

    //автостарт
    if (_tapTimes.length >= 3 && timer == null) {
      startMetronome();
    }

    if (_tapTimes.isNotEmpty &&
        now - _tapTimes.last > 2000) {
      _tapTimes.clear();
    }

    // добавляем тап
    _tapTimes.add(now);

    // храним только последние N тапов
    if (_tapTimes.length > _maxTaps) {
      _tapTimes.removeAt(0);
    }

    // нужно минимум 2 удара
    if (_tapTimes.length < 2) return;

    // считаем интервалы
    List<int> intervals = [];
    for (int i = 1; i < _tapTimes.length; i++) {
      intervals.add(_tapTimes[i] - _tapTimes[i - 1]);
    }

    // средний интервал
    final avg = intervals.reduce((a, b) => a + b) / intervals.length;

    final newBpm = (60000 / avg).round();

    // ограничение
    if (newBpm < 40 || newBpm > 240) return;

    setState(() {
      bpm = newBpm;
    });

    _restartIfRunning();
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

  void _restartIfRunning() {
    if (timer != null) {
      startMetronome();
    }
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
              onChanged: (v) {
                setState(() => bpm = v.round());
                _restartIfRunning();
              },
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
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _handleTapTempo,
              style: ElevatedButton.styleFrom(
                side: const BorderSide(color: Colors.black, width: 2.0),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              ),
              child: const Text(
                "Подобрать темп",
                style: TextStyle(fontSize: 18),
              ),
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

  Widget _buildCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: Colors.green.withOpacity(0.15),
          child: Icon(icon, color: Colors.green),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Меню")),
      body: ListView(
        children: [
          const SizedBox(height: 10),

          _buildCard(
            icon: Icons.music_note,
            title: "Аккорды",
            subtitle: "Просмотр аккордов",
            onTap: () {
              AnalyticsService.incrementChords();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChordsPage()),
              );
            },
          ),

          _buildCard(
            icon: Icons.school,
            title: "Теория",
            subtitle: "Изучение материала",
            onTap: () {
              AnalyticsService.incrementTheory();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TheoryPage()),
              );
            },
          ),

          _buildCard(
            icon: Icons.quiz,
            title: "Тесты",
            subtitle: "Проверка знаний",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TestsPage()),
              );
            },
          ),

          _buildCard(
            icon: Icons.bug_report,
            title: "Ошибки",
            subtitle: "Повтор сложных вопросов",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AllErrorsQuizPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class TestsPage extends StatefulWidget {
  const TestsPage({super.key});

  @override
  State<TestsPage> createState() => _TestsPageState();
}

class _TestsPageState extends State<TestsPage> {
  List<_TestItem> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sections = TheoryApiService.getTheorySections();
    final results = await ProgressService.getAllResults();

    List<_TestItem> list = [];

    for (var s in sections) {
      if (s.quiz != null) {
        final score = results[s.id] ?? 0.0;

        list.add(_TestItem(
          data: s,
          score: score,
        ));
      }
    }

    list.sort((a, b) => a.score.compareTo(b.score));

    setState(() {
      items = list;
    });
  }

  Color _getColor(double score) {
    if (score == 0) return Colors.grey;
    if (score < 0.5) return Colors.red;
    if (score < 0.8) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Тесты")),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Text(
                item.data.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: item.score,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation(
                      _getColor(item.score),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Прогресс: ${(item.score * 100).toStringAsFixed(0)}%",
                  ),
                ],
              ),
              trailing: const Icon(Icons.play_arrow),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuizPage(
                      questions: item.data.quiz!,
                      theoryId: item.data.id,
                    ),
                  ),
                ).then((_) => _load());
              },
            ),
          );
        },
      ),
    );
  }
}

class _TestItem {
  final TheoryData data;
  final double score;

  _TestItem({required this.data, required this.score});
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
  Map<String, double> progress = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ProgressService.getAllResults();
    setState(() {
      progress = data;
    });
  }

  Color _getColor(double score) {
    if (score == 0) return Colors.grey;
    if (score < 0.5) return Colors.red;
    if (score < 0.8) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final sections = TheoryApiService.getTheorySections();

    return Scaffold(
      appBar: AppBar(title: const Text("Теория")),
      body: ListView.builder(
        itemCount: sections.length,
        itemBuilder: (context, index) {
          final s = sections[index];
          final score = progress[s.id] ?? 0.0;

          return Card(
            margin: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Text(
                s.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: score,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation(
                      _getColor(score),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Прогресс: ${(score * 100).toStringAsFixed(0)}%",
                  ),
                ],
              ),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TheoryDetailPage(data: s),
                  ),
                ).then((_) => _load());
              },
            ),
          );
        },
      ),
    );
  }
}

class TheoryDetailPage extends StatelessWidget {
  final TheoryData data;

  const TheoryDetailPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(data.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var section in data.sections)
              _buildSection(section, context),

            const SizedBox(height: 20),

            _buildPracticeBlock(context, data),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(TheorySection section, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.heading,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        _buildContent(section.content, context),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildContent(String content, BuildContext context) {
    final regex = RegExp(r'\[(.*?)\]\((.*?)\)');
    final matches = regex.allMatches(content);

    if (matches.isEmpty) {
      return Text(content, style: const TextStyle(fontSize: 16));
    }

    List<InlineSpan> spans = [];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(
          TextSpan(
            text: content.substring(lastIndex, match.start),
            style: const TextStyle(fontSize: 16, color: Colors.black),
          ),
        );
      }

      final text = match.group(1)!;
      final id = match.group(2)!;

      spans.add(
        WidgetSpan(
          child: GestureDetector(
            onTap: () {
              final target = TheoryApiService.getById(id);
              if (target != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TheoryDetailPage(data: target),
                  ),
                );
              }
            },
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
                fontSize: 16,
              ),
            ),
          ),
        ),
      );

      lastIndex = match.end;
    }

    if (lastIndex < content.length) {
      spans.add(
        TextSpan(
          text: content.substring(lastIndex),
          style: const TextStyle(fontSize: 16, color: Colors.black),
        ),
      );
    }

    return RichText(text: TextSpan(children: spans));
  }

  Widget _buildPracticeBlock(BuildContext context, TheoryData data) {
    return FutureBuilder<List<QuizQuestion>>(
      future: ErrorService.loadAllErrors(),
      builder: (context, snapshot) {
        final allErrors = snapshot.data ?? [];

        // фильтруем ошибки только для этого раздела
        final sectionErrors = allErrors
            .where((q) => q.theoryId == data.id)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Практика",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            // обычный тест
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuizPage(
                      questions: data.quiz!,
                      theoryId: data.id,
                    ),
                  ),
                );
              },
              child: const Text("Тест"),
            ),

            const SizedBox(height: 10),

            // кнопка ошибок (ТОЛЬКО ЕСЛИ ЕСТЬ)
            if (sectionErrors.isNotEmpty)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AllErrorsQuizPage(),
                    ),
                  );
                },
                child: Text("Ошибки (${sectionErrors.length})"),
              ),
          ],
        );
      },
    );
  }
}

//////////////////////////////////////////////////////////////////
//тест
class QuizPage extends StatefulWidget {
  final List<QuizQuestion> questions;
  final String theoryId;
  final bool isErrorMode;

  const QuizPage({
    super.key,
    required this.questions,
    required this.theoryId,
    this.isErrorMode = false,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  int current = 0;
  int score = 0;
  int? selected;
  List<int> wrongAnswers = [];

  void next() async {
    final question = widget.questions[current];

    final isCorrect =
        selected == question.correctIndex;

    if (isCorrect) {
      score++;

      if (widget.isErrorMode) {
        await ErrorService.removeError(
          question.theoryId ?? widget.theoryId,
          question,
        );
      }
    } else {
      wrongAnswers.add(current);
    }

    if (current < widget.questions.length - 1) {
      setState(() {
        current++;
        selected = null;
      });
    } else {
      _showResult();
    }
  }

  void _showResult() async {
    if (!widget.isErrorMode) {
      await ProgressService.saveResult(
        widget.theoryId,
        score,
        widget.questions.length,
      );
    } else {
      // обновляем прогресс по всем затронутым темам
      final ids = widget.questions
          .map((q) => q.theoryId)
          .whereType<String>()
          .toSet();

      for (final id in ids) {
        await ProgressService.updateProgressFromErrors(id);
      }
    }

    await ErrorService.saveErrors(
      widget.theoryId,
      widget.questions,
      wrongAnswers,
    );

    if (score == widget.questions.length) {
      await ErrorService.clearErrors(widget.theoryId);
    }

    if (widget.isErrorMode) {
      await ProgressService.updateProgressFromErrors(widget.theoryId);
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Результат"),
        content: Text(
          "Правильных ответов: $score из ${widget.questions.length}",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text("ОК"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.questions[current];

    return Scaffold(
      appBar: AppBar(
        title: Text("Вопрос ${current + 1}/${widget.questions.length}"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              q.question,
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 20),

            for (int i = 0; i < q.answers.length; i++)
              RadioListTile<int>(
                value: i,
                groupValue: selected,
                title: Text(q.answers[i]),
                onChanged: (v) {
                  setState(() {
                    selected = v;
                  });
                },
              ),

            const Spacer(),

            ElevatedButton(
              onPressed: selected == null ? null : next,
              child: Text(
                current == widget.questions.length - 1
                    ? "Завершить"
                    : "Далее",
              ),
            )
          ],
        ),
      ),
    );
  }
}

//ошибки

class AllErrorsQuizPage extends StatefulWidget {
  const AllErrorsQuizPage({super.key});

  @override
  State<AllErrorsQuizPage> createState() => _AllErrorsQuizPageState();
}

class _AllErrorsQuizPageState extends State<AllErrorsQuizPage> {
  List<QuizQuestion> questions = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final errors = await ErrorService.loadAllErrors();
    setState(() {
      questions = errors;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ошибки"),
        centerTitle: true,
      ),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : questions.isEmpty
          ? const Center(
        child: Text(
          "Ошибок нет 👍",
          style: TextStyle(fontSize: 16),
        ),
      )
          : QuizPage(
        questions: questions,
        theoryId: "all_errors",
        isErrorMode: true,
      ),
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
                  MaterialPageRoute(builder: (_) => DocumentationPage(
                    title: 'Документация',
                    markdownUrl:
                    'https://raw.githubusercontent.com/OGonThaBlock/CourseProject7sem/master/docs/README.md',
                  )),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class DocumentationPage extends StatelessWidget {
  final String title;
  final String markdownUrl;

  const DocumentationPage({
    super.key,
    required this.title,
    required this.markdownUrl,
  });


  static const String _docsBaseUrl =
      'https://raw.githubusercontent.com/OGonThaBlock/CourseProject7sem/master/docs';

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(markdownUrl);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: FutureBuilder<http.Response>(
        future: http.get(uri),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Ошибка загрузки: ${snapshot.error}'),
            );
          }

          final markdown = snapshot.data?.body ?? '';

          return Markdown(
            data: markdown,
            selectable: true,

            imageBuilder: (uri, title, alt) {
              final imageUrl = _resolveUrl(uri.toString());
              return Image.network(imageUrl);
            },

            onTapLink: (text, href, title) {
              if (href == null) return;

              if (href == '/' || href == '/README.md') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                    const DocumentationPage(
                      title: 'Документация',
                      markdownUrl:
                      'https://raw.githubusercontent.com/OGonThaBlock/CourseProject7sem/master/docs/README.md',
                    ),
                  ),
                );
                return;
              }

              final resolvedUrl = _resolveUrl(href);

              if (resolvedUrl.endsWith('.md')) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        DocumentationPage(
                          title: text,
                          markdownUrl: resolvedUrl,
                        ),
                  ),
                );
              } else {
                launchUrl(
                  Uri.parse(resolvedUrl),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
          );
        },
      ),
    );
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http')) return url;

    if (url.startsWith('/')) {
      return '$_docsBaseUrl$url';
    }

    return '$_docsBaseUrl/$url';
  }
}