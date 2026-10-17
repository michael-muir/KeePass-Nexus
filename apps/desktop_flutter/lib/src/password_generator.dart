import 'dart:math';

const passwordCharacterGroups = <String, String>{
  'Uppercase': 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
  'Lowercase': 'abcdefghijklmnopqrstuvwxyz',
  'Numbers': '0123456789',
  'Common symbols': r'!#$%&*+,-./:;=?@^_`~',
  'Brackets': '()[]{}',
  'Operators': '<>|',
  'Quotes': '"\'',
};

const _lookAlikeCharacters = '0O1lI';

const _passphraseWords = <String>[
  'acorn',
  'across',
  'action',
  'advice',
  'amber',
  'anchor',
  'animal',
  'answer',
  'apple',
  'april',
  'arch',
  'area',
  'artist',
  'aspect',
  'audio',
  'autumn',
  'badge',
  'balance',
  'bamboo',
  'banner',
  'basket',
  'beach',
  'beacon',
  'beauty',
  'before',
  'berry',
  'bicycle',
  'bird',
  'bison',
  'blanket',
  'blossom',
  'blue',
  'board',
  'boat',
  'bold',
  'book',
  'border',
  'bottle',
  'bottom',
  'boulder',
  'brain',
  'brave',
  'bread',
  'breeze',
  'brick',
  'bridge',
  'bright',
  'bronze',
  'brush',
  'bubble',
  'bucket',
  'cabin',
  'cactus',
  'camera',
  'camp',
  'candle',
  'canoe',
  'canvas',
  'captain',
  'caramel',
  'carbon',
  'card',
  'carpet',
  'castle',
  'cedar',
  'celery',
  'center',
  'chalk',
  'change',
  'charm',
  'cherry',
  'chess',
  'circle',
  'citron',
  'city',
  'clay',
  'clear',
  'cliff',
  'cloud',
  'clover',
  'coffee',
  'color',
  'comet',
  'compass',
  'coral',
  'corner',
  'cotton',
  'coyote',
  'crane',
  'cream',
  'cricket',
  'crystal',
  'cup',
  'current',
  'cycle',
  'dance',
  'daylight',
  'delta',
  'desert',
  'detail',
  'diamond',
  'dinner',
  'dolphin',
  'door',
  'dream',
  'drift',
  'drum',
  'eagle',
  'earth',
  'echo',
  'edge',
  'elm',
  'ember',
  'engine',
  'evening',
  'falcon',
  'family',
  'feather',
  'fern',
  'field',
  'figure',
  'film',
  'fire',
  'flame',
  'flavor',
  'flight',
  'flower',
  'forest',
  'fossil',
  'fountain',
  'frame',
  'freedom',
  'frost',
  'galaxy',
  'garden',
  'ginger',
  'glass',
  'globe',
  'glory',
  'gold',
  'granite',
  'grape',
  'grass',
  'green',
  'ground',
  'guitar',
  'harbor',
  'harmony',
  'harvest',
  'hazel',
  'heart',
  'helmet',
  'heron',
  'hill',
  'honey',
  'horizon',
  'horse',
  'island',
  'ivory',
  'jade',
  'jacket',
  'jasmine',
  'jazz',
  'jewel',
  'journey',
  'judge',
  'jungle',
  'juniper',
  'kettle',
  'key',
  'kingdom',
  'kitten',
  'kiwi',
  'lake',
  'lantern',
  'lemon',
  'letter',
  'library',
  'light',
  'lilac',
  'linen',
  'lion',
  'lizard',
  'lunar',
  'machine',
  'maple',
  'marble',
  'market',
  'meadow',
  'memory',
  'meteor',
  'midnight',
  'minute',
  'mirror',
  'mist',
  'moment',
  'monarch',
  'monkey',
  'moon',
  'morning',
  'mountain',
  'mouse',
  'music',
  'mustard',
  'napkin',
  'nature',
  'needle',
  'neon',
  'nest',
  'night',
  'north',
  'notebook',
  'number',
  'ocean',
  'olive',
  'orange',
  'orbit',
  'orchid',
  'origin',
  'owl',
  'oxygen',
  'paddle',
  'panda',
  'paper',
  'parcel',
  'parent',
  'party',
  'pebble',
  'pencil',
  'pepper',
  'person',
  'piano',
  'picture',
  'planet',
  'plaza',
  'plum',
  'pocket',
  'poem',
  'polar',
  'pond',
  'prairie',
  'present',
  'prism',
  'purple',
  'puzzle',
  'quartz',
  'quiet',
  'rabbit',
  'radar',
  'radio',
  'rain',
  'raven',
  'recipe',
  'record',
  'reef',
  'remote',
  'ribbon',
  'river',
  'robin',
  'rocket',
  'roof',
  'rose',
  'ruby',
  'saddle',
  'saffron',
  'sailor',
  'salmon',
  'sample',
  'sandal',
  'satin',
  'sauce',
  'scarlet',
  'scene',
  'school',
  'science',
  'season',
  'shadow',
  'shell',
  'silver',
  'simple',
  'singer',
  'sky',
  'smooth',
  'snow',
  'social',
  'solar',
  'solid',
  'song',
  'sound',
  'south',
  'space',
  'spark',
  'sphinx',
  'spice',
  'spider',
  'spirit',
  'spring',
  'square',
  'stadium',
  'star',
  'station',
  'stone',
  'storm',
  'story',
  'stream',
  'summer',
  'sunrise',
  'sunset',
  'symbol',
  'table',
  'talent',
  'temple',
  'theory',
  'thunder',
  'ticket',
  'timber',
  'tomato',
  'topaz',
  'tower',
  'travel',
  'tulip',
  'tunnel',
  'turtle',
  'twelve',
  'unicorn',
  'uniform',
  'unique',
  'valley',
  'velvet',
  'vendor',
  'violet',
  'vision',
  'walnut',
  'water',
  'whale',
  'willow',
  'window',
  'winter',
  'wisdom',
  'wonder',
  'yellow',
  'yonder',
  'zephyr',
  'zinc',
];
final _uniquePassphraseWords = _passphraseWords.toSet().toList(growable: false);
final passphraseWordListSize = _uniquePassphraseWords.length;

enum PasswordQuality { weak, fair, good, strong, excellent }

class GeneratedPassword {
  const GeneratedPassword({
    required this.value,
    required this.entropyBits,
  });

  final String value;
  final double entropyBits;

  int get characterCount => value.runes.length;

  PasswordQuality get quality => qualityForEntropy(entropyBits);
}

PasswordQuality qualityForEntropy(double entropyBits) {
  if (entropyBits < 40) return PasswordQuality.weak;
  if (entropyBits < 60) return PasswordQuality.fair;
  if (entropyBits < 80) return PasswordQuality.good;
  if (entropyBits < 100) return PasswordQuality.strong;
  return PasswordQuality.excellent;
}

GeneratedPassword generateCharacterPassword({
  required int length,
  required Set<String> enabledGroups,
  String customCharacters = '',
  String excludedCharacters = '',
  bool excludeLookAlikes = false,
  bool requireEachGroup = true,
  Random? random,
}) {
  if (length < 1 || length > 128) {
    throw const FormatException('Password length must be between 1 and 128.');
  }

  final rng = random ?? Random.secure();
  final excluded = excludedCharacters.runes.toSet();
  if (excludeLookAlikes) excluded.addAll(_lookAlikeCharacters.runes);

  final selectedGroups = enabledGroups
      .where(passwordCharacterGroups.containsKey)
      .map(
        (name) => passwordCharacterGroups[name]!
            .runes
            .where((character) => !excluded.contains(character))
            .toSet()
            .toList(),
      )
      .toList();
  final characters = <int>{
    ...selectedGroups.expand((group) => group),
    ...customCharacters.runes
        .where((character) => !excluded.contains(character)),
  }.toList();

  if (characters.isEmpty) {
    throw const FormatException('Select at least one character type.');
  }

  if (requireEachGroup) {
    if (selectedGroups.any((group) => group.isEmpty)) {
      throw const FormatException(
        'An enabled character type has no characters after exclusions.',
      );
    }
    if (selectedGroups.length > length) {
      throw const FormatException(
        'Password length must be at least the number of enabled character types.',
      );
    }
  }

  final output = <int>[];
  if (requireEachGroup) {
    for (final group in selectedGroups) {
      output.add(group[rng.nextInt(group.length)]);
    }
  }
  while (output.length < length) {
    output.add(characters[rng.nextInt(characters.length)]);
  }

  for (var index = output.length - 1; index > 0; index--) {
    final otherIndex = rng.nextInt(index + 1);
    final current = output[index];
    output[index] = output[otherIndex];
    output[otherIndex] = current;
  }

  final effectivePoolSize = characters.length;
  final requiredGroupEntropy = requireEachGroup
      ? selectedGroups.fold<double>(
          0,
          (total, group) => total + _log2(group.length),
        )
      : 0;
  final entropy = (length - (requireEachGroup ? selectedGroups.length : 0)) *
          _log2(effectivePoolSize) +
      requiredGroupEntropy;

  return GeneratedPassword(
    value: String.fromCharCodes(output),
    entropyBits: entropy,
  );
}

GeneratedPassword generatePassphrase({
  required int wordCount,
  String separator = '-',
  PassphraseWordCase wordCase = PassphraseWordCase.lowercase,
  Random? random,
}) {
  if (wordCount < 1 || wordCount > 32) {
    throw const FormatException('Word count must be between 1 and 32.');
  }

  final rng = random ?? Random.secure();
  final words = List.generate(
    wordCount,
    (_) => _uniquePassphraseWords[rng.nextInt(_uniquePassphraseWords.length)],
  ).map((word) => switch (wordCase) {
        PassphraseWordCase.lowercase => word,
        PassphraseWordCase.uppercase => word.toUpperCase(),
        PassphraseWordCase.titleCase =>
          '${word[0].toUpperCase()}${word.substring(1)}',
      });
  return GeneratedPassword(
    value: words.join(separator),
    entropyBits: wordCount * _log2(_uniquePassphraseWords.length),
  );
}

enum PassphraseWordCase { lowercase, uppercase, titleCase }

double _log2(int value) => log(value) / ln2;
