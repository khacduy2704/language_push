import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_database.dart';
import '../providers/push_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/word_provider.dart';
import '../widgets/word_form_dialog.dart';
import '../widgets/word_list_item.dart';

class WorldScreen extends StatelessWidget {
  const WorldScreen({super.key});

  Future<void> _onMenuAction(
    BuildContext context,
    WordMenuAction action,
    Word word,
  ) async {
    final WordProvider wordProvider = context.read<WordProvider>();
    final PushProvider pushProvider = context.read<PushProvider>();
    final int intervalMinutes = context
        .read<SettingsProvider>()
        .intervalMinutes;

    switch (action) {
      case WordMenuAction.addForPush:
        if (pushProvider.isWordPushed(word.id)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('"${word.word}" is already in push list.'),
              ),
            );
          }
          return;
        }
        if (!pushProvider.canAddMore) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You can only add up to 5 words in Home list.'),
              ),
            );
          }
          return;
        }
        await pushProvider.addWord(word, intervalMinutes);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added "${word.word}" for push.')),
          );
        }
        return;

      case WordMenuAction.edit:
        final WordFormData? data = await showDialog<WordFormData>(
          context: context,
          builder: (_) => WordFormDialog(
            title: 'Edit Word',
            saveButtonText: 'Update',
            initialWord: word,
          ),
        );
        if (data == null || word.id == null) {
          return;
        }
        try {
          await wordProvider.updateWord(
            word.id!,
            data.word,
            data.partOfSpeech,
            data.meaning,
          );
          pushProvider.replaceWord(
            Word(
              id: word.id,
              word: data.word,
              partOfSpeech: data.partOfSpeech,
              meaning: data.meaning,
            ),
            intervalMinutes,
          );
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not update word. Please try again.'),
              ),
            );
          }
        }
        return;

      case WordMenuAction.delete:
        final bool? confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Delete'),
            content: Text('Delete "${word.word}"?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true || word.id == null) {
          return;
        }
        try {
          await wordProvider.deleteWord(word.id!);
          await pushProvider.removeWord(word, intervalMinutes);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not delete word. Please try again.'),
              ),
            );
          }
        }
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final WordProvider wordProvider = context.watch<WordProvider>();
    final bool showStatusRow = wordProvider.words.isEmpty;
    final bool showLoadingFooter = wordProvider.isLoading && !showStatusRow;
    final int itemCount =
        1 +
        (showStatusRow ? 1 : wordProvider.words.length) +
        (showLoadingFooter ? 1 : 0);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      itemCount: itemCount,
      separatorBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return const SizedBox(height: 22);
        }
        return const Divider(height: 1, thickness: 1, color: Color(0xFFC5CCD5));
      },
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFD6DBE2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: TextField(
              onChanged: context.read<WordProvider>().setSearch,
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                icon: Icon(Icons.search, color: Color(0xFF8E98A7), size: 22),
                hintText: 'Search',
                hintStyle: TextStyle(
                  color: Color(0xFF8E98A7),
                  fontSize: 27 / 2,
                ),
              ),
            ),
          );
        }

        if (showStatusRow) {
          if (wordProvider.isLoading) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (wordProvider.loadError != null) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Text(
                    wordProvider.loadError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF3B4957),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: context.read<WordProvider>().retryFetch,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24, horizontal: 12),
            child: Text(
              'No words found.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF3B4957)),
            ),
          );
        }

        if (showLoadingFooter && index == wordProvider.words.length + 1) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final Word word = wordProvider.words[index - 1];
        return WordListItem(
          word: word,
          onMenuAction: (WordMenuAction action) =>
              _onMenuAction(context, action, word),
        );
      },
    );
  }
}
