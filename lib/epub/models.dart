class Sentence {
  final String text;
  final int index;
  Sentence({required this.text, required this.index});
}

class Paragraph {
  final String rawText;
  final List<Sentence> sentences;
  final int index;
  Paragraph({required this.rawText, required this.sentences, required this.index});
}

class Chapter {
  final String title;
  final List<Paragraph> paragraphs;
  final int index;
  Chapter({required this.title, required this.paragraphs, required this.index});
}

class Book {
  final int? id;
  final String title;
  final String author;
  final String language;
  final String filePath;
  final List<Chapter> chapters;

  Book({
    this.id,
    required this.title,
    required this.author,
    required this.language,
    required this.filePath,
    required this.chapters,
  });

  Book copyWith({int? id, String? language}) => Book(
        id: id ?? this.id,
        title: title,
        author: author,
        language: language ?? this.language,
        filePath: filePath,
        chapters: chapters,
      );
}
