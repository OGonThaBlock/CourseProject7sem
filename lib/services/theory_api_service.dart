import 'package:http/http.dart' as http;
import 'dart:convert';

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

  TheoryData({
    required this.id,
    required this.title,
    required this.sections,
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
    ];
  }

  // Поиск по ID
  static TheoryData? getById(String id) {
    return getTheorySections().firstWhere(
          (e) => e.id == id,
      orElse: () => getTheorySections().first,
    );
  }
}