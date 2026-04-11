import 'package:flutter/material.dart';

import '../data/app_database.dart';

enum WordMenuAction { addForPush, edit, delete }

class WordListItem extends StatelessWidget {
  final Word word;
  final ValueChanged<WordMenuAction> onMenuAction;

  const WordListItem({
    super.key,
    required this.word,
    required this.onMenuAction,
  });

  String get _itemLine {
    return word.meaning.isEmpty
        ? '${word.word} (${word.partOfSpeech})'
        : '${word.word} (${word.partOfSpeech}) ${word.meaning}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _itemLine,
                style: const TextStyle(
                  fontSize: 33 / 2,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3B4957),
                ),
              ),
            ),
          ),
          PopupMenuButton<WordMenuAction>(
            onSelected: onMenuAction,
            icon: const Icon(Icons.more_vert, color: Color(0xFF8994A3)),
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<WordMenuAction>>[
              PopupMenuItem<WordMenuAction>(
                value: WordMenuAction.addForPush,
                child: Text('Add for push'),
              ),
              PopupMenuItem<WordMenuAction>(
                value: WordMenuAction.edit,
                child: Text('Edit'),
              ),
              PopupMenuItem<WordMenuAction>(
                value: WordMenuAction.delete,
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
