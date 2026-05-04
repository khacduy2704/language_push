import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_database.dart';

class PracticeScreen extends StatefulWidget {
  final List<Word> words;

  const PracticeScreen({
    super.key,
    required this.words,
  });

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  late final TextEditingController _answerController;
  late final FocusNode _answerFocusNode;
  late final List<Word> _words;
  final Random _random = Random();
  int _currentIndex = 0;
  bool _showResult = false;
  bool _isCorrect = false;
  List<String> _flashOptions = <String>[];
  String? _selectedFlashAnswer;

  bool get _isTypingTurn => _currentIndex.isEven;

  bool get _canCheck => !_showResult && _answerController.text.trim().isNotEmpty;

  Word get _currentWord => _words[_currentIndex];

  bool get _isLastWord => _currentIndex == _words.length - 1;

  @override
  void initState() {
    super.initState();
    _answerController = TextEditingController();
    _answerController.addListener(_onAnswerChanged);
    _answerFocusNode = FocusNode();
    _words = List<Word>.from(widget.words);
    _prepareFlashOptions();
  }

  @override
  void dispose() {
    _answerController.removeListener(_onAnswerChanged);
    _answerController.dispose();
    _answerFocusNode.dispose();
    super.dispose();
  }

  void _onAnswerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _checkAnswer() {
    final String answer = _answerController.text.trim().toLowerCase();
    final String target = _currentWord.word.trim().toLowerCase();

    setState(() {
      _isCorrect = answer == target;
      _showResult = true;
    });
  }

  void _checkFlashcard(String selectedWord) {
    if (_showResult) {
      return;
    }

    final String selected = selectedWord.trim().toLowerCase();
    final String target = _currentWord.word.trim().toLowerCase();
    setState(() {
      _selectedFlashAnswer = selectedWord;
      _isCorrect = selected == target;
      _showResult = true;
    });
  }

  void _prepareFlashOptions() {
    final String correct = _currentWord.word;
    final List<String> pool = _words
        .map((Word w) => w.word)
        .where((String w) => w.toLowerCase() != correct.toLowerCase())
        .toSet()
        .toList();

    pool.shuffle(_random);

    final List<String> options = <String>[correct];
    for (final String candidate in pool) {
      if (options.length >= 4) {
        break;
      }
      options.add(candidate);
    }

    // Keep a 4-card layout even when there are fewer unique words.
    while (options.length < 4) {
      options.add(correct);
    }

    options.shuffle(_random);
    _flashOptions = options;
  }

  void _nextWord() {
    if (_isLastWord) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _currentIndex += 1;
      _showResult = false;
      _isCorrect = false;
      _answerController.clear();
      _selectedFlashAnswer = null;
      _prepareFlashOptions();
      if (_isTypingTurn) {
        _answerFocusNode.requestFocus();
      }
    });
  }

  String _normalizeInput(String value, int maxLength) {
    final String cleaned = value
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.length <= maxLength) {
      return cleaned;
    }
    return cleaned.substring(0, maxLength);
  }

  Widget _buildDashedInput() {
    final String target = _currentWord.word;
    final String typed = _answerController.text;

    return GestureDetector(
      onTap: _showResult || !_isTypingTurn
          ? null
          : () => _answerFocusNode.requestFocus(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFC8CDD4), width: 1),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 8,
          children: List<Widget>.generate(target.length, (int index) {
            final String targetChar = target[index];
            if (targetChar == ' ') {
              return const SizedBox(width: 12, height: 36);
            }

            final bool hasChar = index < typed.length && typed[index] != ' ';
            final String char = hasChar ? typed[index] : '';

            return SizedBox(
              width: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    height: 26,
                    child: Text(
                      char,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF1E1F22),
                        fontSize: 18,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    height: 2,
                    color: const Color(0xFFB5BAC1),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildFlashcards() {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.2,
      children: _flashOptions.map((String option) {
        final bool isSelected = option == _selectedFlashAnswer;
        final bool isCorrectOption =
            option.toLowerCase() == _currentWord.word.trim().toLowerCase();

        Color backgroundColor = Colors.white;
        Color borderColor = const Color(0xFFC8CDD4);

        if (_showResult && isCorrectOption) {
          backgroundColor = const Color(0xFFD6F5DD);
          borderColor = const Color(0xFF20B63A);
        } else if (_showResult && isSelected && !isCorrectOption) {
          backgroundColor = const Color(0xFFFFD9DC);
          borderColor = const Color(0xFFE65A67);
        }

        return InkWell(
          onTap: _showResult ? null : () => _checkFlashcard(option),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.4),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              option,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF24282E),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String modeLabel = _isTypingTurn ? 'Dien tu' : 'Flashcard';

    return Scaffold(
      backgroundColor: const Color(0xFFE2E6EB),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xFFE2E6EB),
        title: const Text(
          'Practice',
          style: TextStyle(
            color: Color(0xFF3B4957),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                modeLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF7A7F87),
                  fontSize: 30 / 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${_currentWord.meaning.isEmpty ? '(No meaning)' : _currentWord.meaning} (${_currentWord.partOfSpeech})',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 52 / 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              if (_isTypingTurn) ...<Widget>[
                _buildDashedInput(),
                Opacity(
                  opacity: 0,
                  child: SizedBox(
                    height: 1,
                    child: TextField(
                      controller: _answerController,
                      focusNode: _answerFocusNode,
                      enabled: !_showResult,
                      autofocus: true,
                      inputFormatters: <TextInputFormatter>[
                        LengthLimitingTextInputFormatter(_currentWord.word.length),
                      ],
                      onChanged: (String value) {
                        final String normalized =
                            _normalizeInput(value, _currentWord.word.length);
                        if (value == normalized) {
                          return;
                        }
                        _answerController.value = TextEditingValue(
                          text: normalized,
                          selection: TextSelection.collapsed(
                            offset: normalized.length,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ] else ...<Widget>[
                _buildFlashcards(),
              ],
              const Spacer(),
              if (_isTypingTurn)
                Center(
                  child: SizedBox(
                    width: 210,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _canCheck ? _checkAnswer : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFCCD0D5),
                        foregroundColor: const Color(0xFF5F6671),
                        disabledBackgroundColor: const Color(0xFFD4D7DC),
                        disabledForegroundColor: const Color(0xFF8E949D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32),
                        ),
                      ),
                      child: const Text(
                        'Kiem tra',
                        style: TextStyle(
                          fontSize: 34 / 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      bottomSheet: _showResult
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              decoration: BoxDecoration(
                color: _isCorrect ? const Color(0xFF20B63A) : const Color(0xFFE65A67),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _isCorrect ? 'Correct' : 'Incorrect',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_currentWord.word} (${_currentWord.partOfSpeech})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currentWord.meaning,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: SizedBox(
                        width: 220,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _nextWord,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF202020),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          child: Text(
                            _isLastWord ? 'Finish' : 'Tiep tuc',
                            style: const TextStyle(
                              fontSize: 32 / 2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}