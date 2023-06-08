/// A data model class that stores context of the error,
/// i.e. the error and some text to the left and to the left.
class Context {
  /// Text.
  String text;

  /// Offset to the text.
  int offset;

  /// Length of the sentence.
  int length;

  /// Creates a new instance of the [Context] class.
  Context({
    required this.text,
    required this.offset,
    required this.length,
  });

  /// Parse [Context] from json.
  factory Context.fromJson(Map<String, dynamic> json) => Context(
        text: json['text'] as String,
        offset: json['offset'] as int,
        length: json['length'] as int,
      );

  /// Get json from [Context].
  Map<String, dynamic> toJson() => {
        'text': text,
        'offset': offset,
        'length': length,
      };
}
