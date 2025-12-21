import 'package:http/http.dart' as http;
import 'dart:convert';

class TheorySection {
  final String heading;
  final String content;
  TheorySection({required this.heading, required this.content});
}

class TheoryData {
  final String title;
  final List<TheorySection> sections;
  TheoryData({required this.title, required this.sections});

  factory TheoryData.fromJson(Map<String, dynamic> json) {
    final sectionsJson = json['sections'] as List;
    final sections = sectionsJson.map((s) => TheorySection(
      heading: s['heading'],
      content: s['content'],
    )).toList();
    return TheoryData(
      title: json['title'],
      sections: sections,
    );
  }
}

class TheoryApiService {
  static const String _baseUrl = 'http://192.168.0.102:8000';
  static const String _theoryEndpoint = '$_baseUrl/theory';

  /// Загружает теорию с сервера.
  /// Возвращает `null`, если произошла ошибка (нет сети, сервер недоступен и т.п.).
  static Future<TheoryData?> fetchTheoryFromApi() async {
    try {
      final response = await http.get(Uri.parse(_theoryEndpoint));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return TheoryData.fromJson(json);
      }
    } catch (e) {
      // Логирование ошибки можно добавить, если нужно
      // print('Error fetching theory: $e');
    }
    return null;
  }

  /// Возвращает локальные (резервные) данные теории.
  static TheoryData getLocalFallback() {
    return TheoryData(
      title: "Основы музыкальной теории",
      sections: [
        TheorySection(
          heading: "Ноты",
          content: "В западной музыке используется 12 нот в октаве:\nC, C#, D, D#, E, F, F#, G, G#, A, A#, B\n(или по-русски: До, До♯, Ре, Ре♯, Ми, Фа, Фа♯, Соль, Соль♯, Ля, Ля♯, Си).\n\nЭти 12 нот повторяются в каждой октаве — выше или ниже по высоте.",
        ),
        TheorySection(
          heading: "Октава",
          content: "Октава — это интервал между двумя нотами с одинаковым названием, где частота верхней в 2 раза больше нижней.\nНапример: A4 = 440 Гц, A5 = 880 Гц.",
        ),
        TheorySection(
          heading: "Строй и частота",
          content: "Международный стандарт — A4 (Ля первой октавы) = 440 Гц.\nОстальные ноты рассчитываются по формуле:\nf = 440 × 2^(n/12),\nгде n — количество полутонов от A4.",
        ),
        TheorySection(
          heading: "Полутон и тон",
          content: "Минимальный шаг в музыке — полутон (например, от C к C#).\nДва полутона = тон (например, от C к D).",
        ),
        TheorySection(
          heading: "Диез (♯) и бемоль (♭)",
          content: "- Диез (♯) — повышает ноту на полутон (C → C♯).\n- Бемоль (♭) — понижает на полутон (D → D♭).\nC♯ и D♭ — это одна и та же высота (энгармонизм).",
        ),
      ],
    );
  }
}