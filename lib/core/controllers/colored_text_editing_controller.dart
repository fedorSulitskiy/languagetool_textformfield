import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:languagetool_textfield/core/enums/mistake_type.dart';
import 'package:languagetool_textfield/domain/highlight_style.dart';
import 'package:languagetool_textfield/domain/language_check_service.dart';
import 'package:languagetool_textfield/domain/mistake.dart';
import 'package:languagetool_textfield/domain/typedefs.dart';

/// A TextEditingController with overrides buildTextSpan for building
/// marked TextSpans with tap recognizer
class ColoredTextEditingController extends TextEditingController {
  /// Color scheme to highlight mistakes
  final HighlightStyle highlightStyle;

  /// Language tool API index
  final LanguageCheckService languageCheckService;

  /// List which contains Mistake objects spans are built from
  List<Mistake> _mistakes = [];

  // Declare a flag to track ongoing language check requests
  int _lastRequestId = 0;

  /// List of that is used to dispose recognizers after mistakes rebuilt
  final List<TapGestureRecognizer> _recognizers = [];

  /// Callback that will be executed after mistake clicked
  ShowPopupCallback? showPopup;

  Object? _fetchError;

  /// An error that may have occurred during the API fetch.
  Object? get fetchError => _fetchError;

  @override
  set value(TextEditingValue newValue) {
    _handleTextChange(newValue.text);
    super.value = newValue;
  }

  /// Controller constructor
  ColoredTextEditingController({
    required this.languageCheckService,
    this.highlightStyle = const HighlightStyle(),
  });

  /// Generates TextSpan from Mistake list
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final formattedTextSpans = _generateSpans(
      context,
      style: style,
    );

    return TextSpan(
      children: formattedTextSpans.toList(),
    );
  }

  @override
  void dispose() {
    languageCheckService.dispose();
    super.dispose();
  }

  /// Replaces mistake with given replacement
  void replaceMistake(Mistake mistake, String replacement) {
    final mistakes = List<Mistake>.from(_mistakes);
    mistakes.remove(mistake);
    _mistakes = mistakes;
    text = text.replaceRange(mistake.offset, mistake.endOffset, replacement);
    selection = TextSelection.fromPosition(
      TextPosition(offset: mistake.offset + replacement.length),
    );
  }

  /// Clear mistakes list when text mas modified and get a new list of mistakes
  /// via API
  Future<void> _handleTextChange(String newText) async {
    ///set value triggers each time, even when cursor changes its location
    ///so this check avoid cleaning Mistake list when text wasn't really changed
    if (newText == text) return;

    final filteredMistakes = _filterMistakesOnChanged(newText);
    _mistakes = filteredMistakes;

    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    // Set the flag to indicate an ongoing request
    // Increment the request ID to track the most recent request
    final requestId = ++_lastRequestId;

    final mistakesWrapper = await languageCheckService.findMistakes(newText);
    final mistakes = mistakesWrapper?.result();
    _fetchError = mistakesWrapper?.error;

    // Check if a newer request has been initiated during the API call
    if (requestId != _lastRequestId) return;
    _lastRequestId = 0;

    // Update the mistakes list with the new mistakes
    // or fallback to filteredMistakes
    _mistakes = mistakes ?? filteredMistakes;

    notifyListeners();
  }

  /// Generator function to create TextSpan instances
  Iterable<TextSpan> _generateSpans(
    BuildContext context, {
    TextStyle? style,
  }) sync* {
    int currentOffset = 0; // enter index

    for (final Mistake mistake in _mistakes) {
      final mistakeEndOffset = min(mistake.endOffset, text.length);
      if (mistake.offset > mistakeEndOffset) continue;

      /// TextSpan before mistake
      yield TextSpan(
        text: text.substring(
          currentOffset,
          min(mistake.offset, text.length),
        ),
        style: style,
      );

      /// Get a highlight color
      final Color mistakeColor = _getMistakeColor(mistake.type);

      /// Create a gesture recognizer for mistake
      final _onTap = TapGestureRecognizer()
        ..onTapDown = (details) {
          showPopup?.call(context, mistake, details.globalPosition, this);
        };

      /// Adding recognizer to the list for future disposing
      _recognizers.add(_onTap);

      /// Mistake highlighted TextSpan
      yield TextSpan(
        children: [
          TextSpan(
            text: text.substring(mistake.offset, mistakeEndOffset),
            mouseCursor: MaterialStateMouseCursor.clickable,
            style: style?.copyWith(
              backgroundColor: mistakeColor.withOpacity(
                highlightStyle.backgroundOpacity,
              ),
              decoration: highlightStyle.decoration,
              decorationColor: mistakeColor,
              decorationThickness: highlightStyle.mistakeLineThickness,
            ),
            recognizer: _onTap,
          ),
        ],
      );

      currentOffset = min(mistake.endOffset, text.length);
    }

    /// TextSpan after mistake
    yield TextSpan(
      text: text.substring(currentOffset),
      style: style,
    );
  }

  /// Filters the list of mistakes based on the changes
  /// in the text when it is changed.
  List<Mistake> _filterMistakesOnChanged(String newText) {
    final newMistakes = <Mistake>[];

    for (final mistake in _mistakes) {
      if (_isSelectionEncompassingMistake(mistake)) continue;

      final lengthDiscrepancy = newText.length - text.length;
      final newOffset = mistake.offset + lengthDiscrepancy;
      final isTextLengthIncreased = newText.length > text.length;

      if (isTextLengthIncreased &&
          _isSelectionBaseWithinAndAtMistakeBoundaries(mistake)) continue;

      if (!isTextLengthIncreased &&
          (_isSelectionBaseWithinAndAtMistakeBoundaries(mistake) ||
              _isSelectionWithinMistake(mistake))) continue;

      final isTextLengthIncreasedAndBaseBeforeMistake =
          isTextLengthIncreased && _isSelectionBaseBeforeMistake(mistake);
      final isTextLengthNotIncreasedAndBaseBeforeOrAtMistake =
          !isTextLengthIncreased && _isSelectionBaseBeforeOrAtMistake(mistake);

      isTextLengthIncreasedAndBaseBeforeMistake ||
              isTextLengthNotIncreasedAndBaseBeforeOrAtMistake
          ? newMistakes.add(mistake.copyWith(offset: newOffset))
          : newMistakes.add(mistake);
    }

    return newMistakes;
  }

  /// Returns color for mistake TextSpan style
  Color _getMistakeColor(MistakeType type) {
    switch (type) {
      case MistakeType.misspelling:
        return highlightStyle.misspellingMistakeColor;
      case MistakeType.typographical:
        return highlightStyle.typographicalMistakeColor;
      case MistakeType.grammar:
        return highlightStyle.grammarMistakeColor;
      case MistakeType.uncategorized:
        return highlightStyle.uncategorizedMistakeColor;
      case MistakeType.nonConformance:
        return highlightStyle.nonConformanceMistakeColor;
      case MistakeType.style:
        return highlightStyle.styleMistakeColor;
      case MistakeType.other:
        return highlightStyle.otherMistakeColor;
    }
  }

  bool _isSelectionBaseBeforeMistake(Mistake mistake) =>
      selection.base.offset < mistake.offset;

  bool _isSelectionBaseBeforeOrAtMistake(Mistake mistake) =>
      selection.base.offset <= mistake.offset;

  bool _isSelectionWithinMistake(Mistake mistake) =>
      (selection.end > mistake.offset && selection.end <= mistake.endOffset) ||
      (selection.start > mistake.offset &&
          selection.start <= mistake.endOffset);

  bool _isSelectionBaseWithinAndAtMistakeBoundaries(Mistake mistake) =>
      selection.base.offset >= mistake.offset &&
      selection.base.offset <= mistake.endOffset;

  bool _isSelectionEncompassingMistake(Mistake mistake) =>
      selection.start <= mistake.offset && selection.end >= mistake.endOffset;
}
