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
}

class QuizQuestion {
  final String question;
  final List<String> answers;
  final int correctIndex;

  QuizQuestion({
    required this.question,
    required this.answers,
    required this.correctIndex,
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
            question: "Что такое BPM?",
            answers: ["Скорость", "Громкость", "Высота", "Тон"],
            correctIndex: 0,
          ),
          QuizQuestion(
            question: "Сколько долей в 4/4?",
            answers: ["2", "3", "4", "8"],
            correctIndex: 2,
          ),
          QuizQuestion(
            question: "Что задаёт метроном?",
            answers: ["Ритм", "Ноты", "Гамму", "Аккорды"],
            correctIndex: 0,
          ),
          QuizQuestion(
            question: "Чем измеряется темп?",
            answers: ["Гц", "BPM", "ДБ", "Ватты"],
            correctIndex: 1,
          ),
          QuizQuestion(
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
            question: "Минимальный интервал?",
            answers: ["Тон", "Полутон", "Октава", "Квинта"],
            correctIndex: 1,
          ),
          QuizQuestion(
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