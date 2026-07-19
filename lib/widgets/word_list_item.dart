import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/pronunciation_service.dart';

enum WordMenuAction { addForPush, edit, delete }

class WordListItem extends StatefulWidget {
  final Word word;
  final ValueChanged<WordMenuAction>? onMenuAction;
  final bool showMenu;

  const WordListItem({
    super.key,
    required this.word,
    this.onMenuAction,
    this.showMenu = true,
  });

  @override
  State<WordListItem> createState() => _WordListItemState();
}

class _WordListItemState extends State<WordListItem> {
  final PronunciationService _pronunciationService = PronunciationService();
  bool _hasAudio = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _checkAudioCache();
    AppDatabase.instance.audioCacheVersion.addListener(_onAudioCacheChanged);
  }

  @override
  void didUpdateWidget(WordListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word.word != widget.word.word) {
      _checkAudioCache();
    }
  }

  @override
  void dispose() {
    AppDatabase.instance.audioCacheVersion.removeListener(_onAudioCacheChanged);
    _pronunciationService.dispose();
    super.dispose();
  }

  void _onAudioCacheChanged() {
    _checkAudioCache();
  }

  Future<void> _playAudio() async {
    if (_isPlaying) return;
    setState(() => _isPlaying = true);
    try {
      await _pronunciationService.playWord(widget.word.word);
      // After playing, refresh cache status (download may have happened)
      final bool cached =
          await _pronunciationService.isAudioCached(widget.word.word);
      if (mounted) {
        setState(() => _hasAudio = cached);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('Exception: ', ''),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    }
  }

  Future<void> _checkAudioCache() async {
    final bool cached =
        await _pronunciationService.isAudioCached(widget.word.word);
    if (mounted) {
      setState(() => _hasAudio = cached);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String wordText = widget.word.word.trim();
    final String partOfSpeechText = widget.word.partOfSpeech.trim();
    final String meaningText = widget.word.meaning.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    wordText,
                    style: const TextStyle(
                      fontSize: 33 / 2,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3B4957),
                    ),
                  ),
                  if (partOfSpeechText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '($partOfSpeechText)',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF3B4957),
                        ),
                      ),
                    ),
                  if (meaningText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        meaningText,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3B4957),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: _playAudio,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                _isPlaying
                    ? Icons.hourglass_top_rounded
                    : Icons.volume_up_rounded,
                size: 20,
                color: _hasAudio
                    ? const Color(0xFF4B7BE5)
                    : const Color(0xFFBCC4CE),
              ),
            ),
          ),
          if (widget.showMenu)
            PopupMenuButton<WordMenuAction>(
              onSelected: widget.onMenuAction,
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
