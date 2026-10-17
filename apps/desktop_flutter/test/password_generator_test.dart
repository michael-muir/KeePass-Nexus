import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:keeppass_nexus/src/password_generator.dart';

void main() {
  test('character passwords honor length, selected groups, and exclusions', () {
    final password = generateCharacterPassword(
      length: 28,
      enabledGroups: const {
        'Uppercase',
        'Lowercase',
        'Numbers',
        'Common symbols',
      },
      excludeLookAlikes: true,
      random: Random(42),
    );

    expect(password.characterCount, 28);
    expect(password.value, matches(RegExp(r'[A-Z]')));
    expect(password.value, matches(RegExp(r'[a-z]')));
    expect(password.value, matches(RegExp(r'[0-9]')));
    expect(password.value, matches(RegExp(r'[!#$%&*+,\-./:;=?@^_`~]')));
    expect(password.value, isNot(matches(RegExp(r'[0O1lI]'))));
    expect(password.entropyBits, greaterThan(100));
  });

  test(
      'custom characters can be used alone and excluded characters are omitted',
      () {
    final password = generateCharacterPassword(
      length: 12,
      enabledGroups: const {},
      customCharacters: 'xyyz',
      excludedCharacters: 'z',
      requireEachGroup: false,
      random: Random(7),
    );

    expect(password.characterCount, 12);
    expect(password.value, matches(RegExp(r'^[xy]+$')));
    expect(password.value, isNot(contains('z')));
  });

  test('passphrases respect word count, separator, case, and entropy', () {
    final phrase = generatePassphrase(
      wordCount: 8,
      separator: '.',
      wordCase: PassphraseWordCase.titleCase,
      random: Random(19),
    );
    final words = phrase.value.split('.');

    expect(words, hasLength(8));
    expect(words, everyElement(matches(RegExp(r'^[A-Z][a-z]*$'))));
    expect(phrase.characterCount, phrase.value.length);
    expect(phrase.entropyBits, greaterThanOrEqualTo(64));

    final recommendedPhrase = generatePassphrase(
      wordCount: 13,
      random: Random(20),
    );
    expect(recommendedPhrase.quality, PasswordQuality.excellent);
  });

  test('invalid character constraints return an explicit validation error', () {
    expect(
      () => generateCharacterPassword(
        length: 8,
        enabledGroups: const {'Lowercase'},
        excludedCharacters: 'abcdefghijklmnopqrstuvwxyz',
      ),
      throwsFormatException,
    );
  });
}
