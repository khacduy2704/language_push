import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_database.dart';
import '../data/dictionary_file_search.dart';
import '../data/pronunciation_service.dart';
import '../providers/push_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/word_provider.dart';

class MeaningItem {
  final String text;
  final bool isExample;

  MeaningItem({required this.text, required this.isExample});
}

class MeaningGroup {
  final String pos;
  final List<MeaningItem> items;

  MeaningGroup({required this.pos, required this.items});
}

class WordDetailScreen extends StatefulWidget {
  final dynamic item;

  const WordDetailScreen({required this.item, super.key});

  @override
  State<WordDetailScreen> createState() => _WordDetailScreenState();
}

class _WordDetailScreenState extends State<WordDetailScreen> {
  final DictionaryFileSearch _dictSearch = DictionaryFileSearch();
  final PronunciationService _pronunciationService = PronunciationService();
  late String _word;
  late String _ipa;
  late String _partOfSpeech;
  late String _meaning;
  late List<MeaningGroup> _meaningGroups;
  bool _isLoadingMeaning = false;
  bool _isPlayingAudio = false;
  final Set<String> _addedMeanings = <String>{};

  Future<void> _playPronunciation() async {
    if (_isPlayingAudio) {
      return;
    }

    setState(() {
      _isPlayingAudio = true;
    });

    try {
      await _pronunciationService.playWord(_word);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlayingAudio = false;
      });
    }
  }

  Future<void> _addToList(BuildContext context, String meaningText) async {
    final WordProvider wordProvider = context.read<WordProvider>();
    final PushProvider pushProvider = context.read<PushProvider>();
    final int intervalMinutes =
        context.read<SettingsProvider>().intervalMinutes;

    try {
      Word? targetWord = await AppDatabase.instance.findWord(
        word: _word,
        meaning: meaningText,
      );

      if (targetWord?.id != null && pushProvider.isWordPushed(targetWord!.id)) {
        if (!context.mounted) return;
        setState(() => _addedMeanings.add(meaningText));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$_word" is already in the push list.'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      if (!pushProvider.canAddMore) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Push list is full (max 5).'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      if (targetWord == null) {
        await wordProvider.addWord(_word, _partOfSpeech, meaningText);
        targetWord = await AppDatabase.instance.findWord(
          word: _word,
          meaning: meaningText,
        );
      }

      if (targetWord != null) {
        final bool added = await pushProvider.addWord(targetWord, intervalMinutes);
        if (!context.mounted) return;
        if (added) {
          setState(() => _addedMeanings.add(meaningText));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"$_word" added to push list.'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add word. Please try again.')),
      );
    }
  }

  List<MeaningGroup> _parseMeanings(String meaning) {
    final List<MeaningGroup> groups = <MeaningGroup>[];
    if (meaning.trim().isEmpty) {
      return groups;
    }

    // Split by * to find POS sections
    final List<String> posBlocks = meaning.split('*');
    
    for (int blockIndex = 1; blockIndex < posBlocks.length; blockIndex++) {
      final String block = posBlocks[blockIndex];
      final List<String> lines = block
          .split('\n')
          .map((String line) => line.trim())
          .where((String line) => line.isNotEmpty)
          .toList();

      if (lines.isEmpty) continue;

      // First line is the POS label
      final String posLabel = lines[0];
      final List<MeaningItem> items = <MeaningItem>[];

      // Parse meanings and examples from remaining lines
      for (int i = 1; i < lines.length; i++) {
        final String line = lines[i];
        
        if (line.startsWith('-') || line.startsWith('=')) {
          final String content = line.substring(1).trim();
          if (content.isNotEmpty) {
            items.add(MeaningItem(text: content, isExample: false));
          }
        } else if (line.startsWith('!')) {
          final String content = line.substring(1).trim();
          if (content.isNotEmpty) {
            items.add(MeaningItem(text: content, isExample: true));
          }
        } else if (line.isNotEmpty && !line.startsWith('@')) {
          // Regular content without marker - treat as meaning
          items.add(MeaningItem(text: line, isExample: false));
        }
      }

      if (items.isNotEmpty) {
        groups.add(MeaningGroup(pos: posLabel, items: items));
      }
    }

    return groups;
  }

  @override
  void initState() {
    super.initState();
    if (widget.item is Word) {
      final Word word = widget.item as Word;
      _word = word.word;
      _ipa = '';
      _partOfSpeech = word.partOfSpeech;
      _meaning = word.meaning;
    } else if (widget.item is DictionaryEntry) {
      final DictionaryEntry entry = widget.item as DictionaryEntry;
      _word = entry.word;
      _ipa = entry.ipa;
      _partOfSpeech = entry.partOfSpeech;
      _meaning = entry.meaning;
    } else if (widget.item is DictWord) {
      final DictWord entry = widget.item as DictWord;
      _word = entry.word;
      _ipa = entry.ipa;
      _partOfSpeech = entry.partOfSpeech;
      _meaning = entry.meaning;
      _isLoadingMeaning = true;
      _loadMeaningFromFile(entry);
    }
    _meaningGroups = _parseMeanings(_meaning);
  }

  Future<void> _loadMeaningFromFile(DictWord entry) async {
    try {
      final String fullMeaning = await _dictSearch.loadMeaning(entry);
      if (!mounted) {
        return;
      }

      setState(() {
        _meaning = fullMeaning;
        _meaningGroups = _parseMeanings(_meaning);
        if (_partOfSpeech.isEmpty && _meaningGroups.isNotEmpty) {
          _partOfSpeech = _meaningGroups.first.pos;
        }
        _isLoadingMeaning = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingMeaning = false;
      });
    }
  }

  @override
  void dispose() {
    _pronunciationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFE2E6EB),
        centerTitle: true,
        title: Text(
          _word,
          style: const TextStyle(
            color: Color(0xFF3B4957),
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Color(0xFF3B4957)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Word header with pronunciation
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _word,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3B4957),
                        ),
                      ),
                      if (_ipa.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _ipa,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF8994A3),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isPlayingAudio ? null : _playPronunciation,
                  icon: Icon(
                    _isPlayingAudio ? Icons.hourglass_top : Icons.volume_up,
                    color: const Color(0xFF3B4957),
                  ),
                  tooltip: 'Listen pronunciation',
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Part of speech tags
            if (_partOfSpeech.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Wrap(
                  spacing: 8,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F0FF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFB3D9FF),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _partOfSpeech,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0066CC),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Vietnamese label
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Tiếng Việt',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8994A3),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            if (_isLoadingMeaning)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            // Meanings with section headers
            else if (_meaningGroups.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildMeaningsList(),
              )
            else
              Center(
                child: Text(
                  'No meanings available',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMeaningsList() {
    final List<Widget> widgets = <Widget>[];
    int globalMeaningNumber = 1;
    String lastPos = '';

    for (final MeaningGroup group in _meaningGroups) {
      final List<MeaningItem> meanings =
          group.items.where((MeaningItem item) => !item.isExample).toList();

      if (meanings.isEmpty) continue;

      // Add POS section header if it's different from last
      if (group.pos.isNotEmpty &&
          group.pos != 'null' &&
          group.pos != lastPos) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFB3D9FF),
                width: 1,
              ),
            ),
            child: Text(
              group.pos,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF0066CC),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ));
        lastPos = group.pos;
      }

      // Add each meaning
      for (int i = 0; i < meanings.length; i++) {
        final MeaningItem meaning = meanings[i];
        final String displayText = meaning.text;

        // Find examples that follow this meaning
        final List<MeaningItem> followingExamples = <MeaningItem>[];
        bool foundThisMeaning = false;
        for (final MeaningItem item in group.items) {
          if (item.text == displayText && !item.isExample) {
            foundThisMeaning = true;
          } else if (foundThisMeaning &&
              item.isExample &&
              followingExamples.length < 2) {
            followingExamples.add(item);
          } else if (foundThisMeaning && !item.isExample) {
            break;
          }
        }

        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: Text(
                      '$globalMeaningNumber.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF3B4957),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      displayText,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF3B4957),
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _addedMeanings.contains(displayText)
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF4CAF50),
                            ),
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 14,
                            color: Color(0xFF4CAF50),
                          ),
                        )
                      : GestureDetector(
                          onTap: () => _addToList(
                            context,
                            displayText,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0066CC),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Add to push',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                ],
              ),
              // Examples under this meaning
              ...followingExamples.map((MeaningItem example) {
                return Padding(
                  padding: const EdgeInsets.only(
                    left: 24,
                    top: 6,
                  ),
                  child: Text(
                    '* ${example.text}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF666666),
                      height: 1.4,
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        ));

        globalMeaningNumber++;
      }
    }

    return widgets;
  }
}
