import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:push_language/data/dictionary_file_search.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'offline dictionary migration reference rankings and byte offsets',
    () async {
      final Directory documents = await Directory.systemTemp.createTemp(
        'dictionary_parity_',
      );
      const MethodChannel channel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return documents.path;
        }
        throw MissingPluginException(
          'Unexpected path-provider call: ${call.method}',
        );
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
        await documents.delete(recursive: true);
      });

      final DictionaryFileSearch dictionary = DictionaryFileSearch();
      final cases = <String, List<(String, int)>>{
        'apple': [
          ('apple', 417966),
          ('apple-brandy', 418421),
          ('apple-butter', 418480),
          ('apple-cart', 418558),
          ('apple-cheecked', 418684),
        ],
        'hello': [
          ('hello', 4061095),
          ('phelloderm', 6531644),
          ('phellogen', 6531717),
          ('phellodermal', 13076387),
          ('phellogenetic', 13076418),
        ],
        'computer': [
          ('computer', 1644433),
          ('computer', 10689697),
          ('computer', 14269482),
          ('computerize', 1644539),
          ('computer analyst', 10689800),
        ],
        'ppy': [
          ('chappy', 1319338),
          ('chippy', 1373230),
          ('choppy', 1387005),
          ('dippy', 2337602),
          ('gappy', 3595139),
        ],
        'xy': [
          ('xylem', 10502261),
          ('xylocarp', 10502335),
          ('xylocarpous', 10502432),
          ('xylograph', 10502518),
          ('xylographer', 10502579),
        ],
      };
      for (final entry in cases.entries) {
        final results = await dictionary.search(query: entry.key, limit: 5);
        expect(
          results.map((word) => (word.word, word.offset)).toList(),
          entry.value,
          reason: entry.key,
        );
      }
      final apple = (await dictionary.search(query: 'apple')).first;
      expect(apple.ipa, "/'æpl/");
      expect(apple.meaning, 'quả táo');
      expect(apple.partOfSpeech, 'danh từ');
      final meaning = await dictionary.loadMeaning(apple);
      expect(meaning, contains("!Adam's apple"));
      expect(meaning, contains('con sâu bỏ rầu nồi canh'));
      expect(meaning, isNot(contains('@apple-brandy')));
    },
  );
}
