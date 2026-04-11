import 'package:flutter/material.dart';

import '../data/app_database.dart';

class WordFormData {
  final String word;
  final String partOfSpeech;
  final String meaning;

  const WordFormData({
    required this.word,
    required this.partOfSpeech,
    required this.meaning,
  });
}

class _PartOfSpeechOption {
  final String label;
  final String value;

  const _PartOfSpeechOption({required this.label, required this.value});
}

class WordFormDialog extends StatefulWidget {
  final String title;
  final String saveButtonText;
  final Word? initialWord;

  const WordFormDialog({
    super.key,
    required this.title,
    required this.saveButtonText,
    this.initialWord,
  });

  @override
  State<WordFormDialog> createState() => _WordFormDialogState();
}

class _WordFormDialogState extends State<WordFormDialog> {
  static const List<_PartOfSpeechOption> _partsOfSpeech =
      <_PartOfSpeechOption>[
    _PartOfSpeechOption(label: 'Noun - n', value: 'n'),
    _PartOfSpeechOption(label: 'Verb - v', value: 'v'),
    _PartOfSpeechOption(label: 'Adjective - adj', value: 'adj'),
    _PartOfSpeechOption(label: 'Adverb - adv', value: 'adv'),
    _PartOfSpeechOption(label: 'None', value: 'None'),
  ];

  final TextEditingController _wordController = TextEditingController();
  final TextEditingController _meaningController = TextEditingController();
  String _selectedPOSLabel = 'None';

  @override
  void initState() {
    super.initState();
    final Word? initial = widget.initialWord;
    if (initial == null) {
      return;
    }
    _wordController.text = initial.word;
    _meaningController.text = initial.meaning;
    final bool hasLabel = _partsOfSpeech
        .any((_PartOfSpeechOption o) => o.value == initial.partOfSpeech);
    if (hasLabel) {
      _selectedPOSLabel = _partsOfSpeech
          .firstWhere((_PartOfSpeechOption o) => o.value == initial.partOfSpeech)
          .label;
    }
  }

  @override
  void dispose() {
    _wordController.dispose();
    _meaningController.dispose();
    super.dispose();
  }

  void _onSave() {
    final String word = _wordController.text.trim();
    if (word.isEmpty) {
      return;
    }
    final String meaning = _meaningController.text.trim();
    final _PartOfSpeechOption selected = _partsOfSpeech.firstWhere(
      (_PartOfSpeechOption o) => o.label == _selectedPOSLabel,
      orElse: () => const _PartOfSpeechOption(label: 'None', value: 'None'),
    );
    Navigator.of(context).pop(
      WordFormData(word: word, partOfSpeech: selected.value, meaning: meaning),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        padding: const EdgeInsets.all(24),
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _wordController,
              decoration: InputDecoration(
                hintText: 'Placeholder',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Parts of speech',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButton<String>(
                isExpanded: true,
                underline: const SizedBox(),
                value: _selectedPOSLabel,
                onChanged: (String? newValue) {
                  if (newValue == null) {
                    return;
                  }
                  setState(() => _selectedPOSLabel = newValue);
                },
                items: _partsOfSpeech
                    .map<DropdownMenuItem<String>>(
                      (_PartOfSpeechOption option) => DropdownMenuItem<String>(
                        value: option.label,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(option.label),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Meaning',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _meaningController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Placeholder',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[400],
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 12,
                  ),
                ),
                onPressed: _onSave,
                child: Text(widget.saveButtonText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
