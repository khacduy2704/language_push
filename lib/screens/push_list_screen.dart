import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_database.dart';
import '../providers/push_provider.dart';

class PushListScreen extends StatelessWidget {
  const PushListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Word> pushedWords = context.watch<PushProvider>().pushedWords;

    if (pushedWords.isEmpty) {
      return const Center(
        child: Text(
          'No words selected for push yet',
          style: TextStyle(fontSize: 16, color: Color(0xFF5A6775)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: pushedWords.length,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1, thickness: 1, color: Color(0xFFC5CCD5)),
      itemBuilder: (BuildContext context, int index) {
        final Word word = pushedWords[index];
        final String itemLine = word.meaning.isEmpty
            ? '${word.word} (${word.partOfSpeech})'
            : '${word.word} (${word.partOfSpeech}) ${word.meaning}';

        return Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
          child: Text(
            itemLine,
            style: const TextStyle(
              fontSize: 33 / 2,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3B4957),
            ),
          ),
        );
      },
    );
  }
}
