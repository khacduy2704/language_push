import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_database.dart';
import '../providers/push_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/word_list_item.dart';

class PushListScreen extends StatelessWidget {
  const PushListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final PushProvider pushProvider = context.watch<PushProvider>();
    final List<Word> pushedWords = pushProvider.pushedWords;

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

        return Dismissible(
          key: ValueKey<int?>(word.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            color: const Color(0xFFFF3B30),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          confirmDismiss: (_) async {
            return showDialog<bool>(
              context: context,
              builder: (BuildContext dialogContext) => AlertDialog(
                title: const Text('Delete'),
                content: Text('Remove "${word.word}" from push list?'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('No'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF3B30),
                    ),
                    child: const Text('Yes'),
                  ),
                ],
              ),
            );
          },
          onDismissed: (_) async {
            final int minutes =
                context.read<SettingsProvider>().intervalMinutes;
            await context.read<PushProvider>().removeWord(word, minutes);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('Removed "${word.word}" from push list.')),
              );
            }
          },
          child: WordListItem(
            word: word,
            showMenu: false,
          ),
        );
      },
    );
  }
}
