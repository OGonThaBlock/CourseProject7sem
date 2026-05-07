import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ProgressService {
  static const _prefix = "quiz_score_";

  static Future<void> saveResult(String theoryId, int score, int total) async {
    final prefs = await SharedPreferences.getInstance();
    final percent = score / total;
    await prefs.setDouble("$_prefix$theoryId", percent);
  }

  static Future<double> getResult(String theoryId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble("$_prefix$theoryId") ?? 0.0;
  }

  static Future<Map<String, double>> getAllResults() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    Map<String, double> results = {};

    for (var key in keys) {
      if (key.startsWith(_prefix)) {
        final id = key.replaceFirst(_prefix, '');
        results[id] = prefs.getDouble(key) ?? 0.0;
      }
    }

    return results;
  }

  static Future<void> updateProgressFromErrors(String theoryId) async {
    final theory = TheoryApiService.getById(theoryId);
    if (theory == null || theory.quiz == null) return;

    final total = theory.quiz!.length;

    final errors = await ErrorService.loadErrors(
      theoryId,
      theory.quiz!,
    );

    final correct = total - errors.length;
    final percent = correct / total;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble("$_prefix$theoryId", percent);
  }
}

class QuizQuestion {
  final String question;
  final List<String> answers;
  final int correctIndex;
  final String? theoryId;

  QuizQuestion({
    required this.question,
    required this.answers,
    required this.correctIndex,
    this.theoryId,
  });
}

class TheorySection {
  final String heading;
  final String content;

  TheorySection({
    required this.heading,
    required this.content,
  });
}

class TheoryData {
  final String id;
  final String title;
  final List<TheorySection> sections;
  final List<QuizQuestion>? quiz;

  TheoryData({
    required this.id,
    required this.title,
    required this.sections,
    this.quiz,
  });
}

class ErrorService {
  static String _key(String id) => "quiz_errors_$id";

  static String _makeKey(QuizQuestion q) => q.question;

  static Future<void> saveErrors(
      String theoryId,
      List<QuizQuestion> questions,
      List<int> wrongIndexes,
      ) async {
    final prefs = await SharedPreferences.getInstance();

    final existing = prefs.getStringList(_key(theoryId)) ?? [];

    for (final i in wrongIndexes) {
      final q = questions[i].question;

      if (!existing.contains(q)) {
        existing.add(q);
      }
    }

    await prefs.setStringList(_key(theoryId), existing);
  }

  static Future<List<QuizQuestion>> loadErrors(
      String theoryId,
      List<QuizQuestion> allQuestions,
      ) async {
    final prefs = await SharedPreferences.getInstance();

    final saved = prefs.getStringList(_key(theoryId)) ?? [];

    return allQuestions.where((q) {
      return saved.contains(q.question);
    }).toList();
  }

  static Future<void> clearErrors(String theoryId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(theoryId));
  }

  static Future<List<QuizQuestion>> loadAllErrors() async {
    final prefs = await SharedPreferences.getInstance();

    final keys = prefs.getKeys().where((k) => k.startsWith("quiz_errors_"));

    List<QuizQuestion> all = [];

    for (final key in keys) {
      final ids = prefs.getStringList(key) ?? [];

      final theoryId = key.replaceFirst("quiz_errors_", "");
      final theory = TheoryApiService.getById(theoryId);

      if (theory == null || theory.quiz == null) continue;

      for (final q in theory.quiz!) {
        if (ids.contains(q.question)) {
          all.add(q);
        }
      }
    }

    return all;
  }

  static Future<void> removeError(
      String theoryId,
      QuizQuestion question,
      ) async {
    final prefs = await SharedPreferences.getInstance();

    final key = _key(theoryId);

    final existing = prefs.getStringList(key) ?? [];

    existing.remove(question.question);

    await prefs.setStringList(key, existing);
  }
}

class TheoryApiService {
  static List<TheoryData> getTheorySections() {
    return [
      TheoryData(
        id: "basic",
        title: "Раздел 1: Основы",
        sections: [
          TheorySection(
            heading: "Ноты",
            content:
            "C, D, E, F, G, A, B — основные ноты.\n\nПерейти к [Раздел 2](advanced)",
          ),
          TheorySection(
            heading: "Октава",
            content:
            "Октава — удвоение частоты.\n\nПодробнее в [Продвинутом разделе](advanced)",
          ),
        ],
      ),

      TheoryData(
        id: "advanced",
        title: "Раздел 2: Продвинутое",
        sections: [
          TheorySection(
            heading: "Интервалы",
            content:
            "Расстояние между нотами.\n\nВернуться к [Основам](basic)",
          ),
          TheorySection(
            heading: "Аккорды",
            content: "Сочетание 3 и более нот.",
          ),
        ],
      ),

      TheoryData(
        id: "rhythm",
        title: "Раздел 3: Ритм",
        sections: [
          TheorySection(
            heading: "Ритм",
            content: "Ритм — это организация длительностей звуков.",
          ),
        ],
        quiz: [
          QuizQuestion(
            theoryId: "rhythm",
            question: "Что такое BPM?",
            answers: ["Скорость", "Громкость", "Высота", "Тон"],
            correctIndex: 0,
          ),
          QuizQuestion(
            theoryId: "rhythm",
            question: "Сколько долей в 4/4?",
            answers: ["2", "3", "4", "8"],
            correctIndex: 2,
          ),
          QuizQuestion(
            theoryId: "rhythm",
            question: "Что задаёт метроном?",
            answers: ["Ритм", "Ноты", "Гамму", "Аккорды"],
            correctIndex: 0,
          ),
          QuizQuestion(
            theoryId: "rhythm",
            question: "Чем измеряется темп?",
            answers: ["Гц", "BPM", "ДБ", "Ватты"],
            correctIndex: 1,
          ),
          QuizQuestion(
            theoryId: "rhythm",
            question: "Самый распространённый размер?",
            answers: ["3/4", "6/8", "4/4", "2/2"],
            correctIndex: 2,
          ),
        ],
      ),

      TheoryData(
        id: "hearing",
        title: "Раздел 4: Слух",
        sections: [
          TheorySection(
            heading: "Музыкальный слух",
            content: "Способность распознавать высоту и интервалы.",
          ),
        ],
        quiz: [
          QuizQuestion(
            theoryId: "hearing",
            question: "Что такое интервал?",
            answers: [
              "Разница высот",
              "Громкость",
              "Темп",
              "Ритм"
            ],
            correctIndex: 0,
          ),
          QuizQuestion(
            theoryId: "hearing",
            question: "Что развивает слух?",
            answers: [
              "Практика",
              "Сон",
              "Еда",
              "Тишина"
            ],
            correctIndex: 0,
          ),
          QuizQuestion(
            theoryId: "hearing",
            question: "Минимальный интервал?",
            answers: ["Тон", "Полутон", "Октава", "Квинта"],
            correctIndex: 1,
          ),
          QuizQuestion(
            theoryId: "hearing",
            question: "Октава — это?",
            answers: [
              "x2 частоты",
              "x3",
              "x4",
              "x10"
            ],
            correctIndex: 0,
          ),
          QuizQuestion(
            theoryId: "hearing",
            question: "Что важно для слуха?",
            answers: [
              "Регулярность",
              "Случайность",
              "Шум",
              "Перерыв"
            ],
            correctIndex: 0,
          ),
        ],
      ),
    ];
  }

  static TheoryData? getById(String id) {
    try {
      return getTheorySections().firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }
}