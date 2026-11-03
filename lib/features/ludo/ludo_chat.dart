/// In-match Ludo chat: tap phrases, emojis, or custom text (online relays text).
abstract final class LudoChat {
  static const maxCustomLength = 80;

  static const phrases = [
    'Good luck!',
    'Nice move!',
    'Well played!',
    'Hurry up!',
    'Thanks!',
    'Sorry!',
    'Oops!',
    'So close!',
    'Great game!',
    'One more round?',
    'I am winning!',
    'Come on!',
    'Unlucky!',
    'Lucky roll!',
    'Watch this!',
    'No way!',
    'Yes!',
    'Please wait',
    'Ready?',
    'Good game',
    'Focus!',
    'Almost there',
    'Not again!',
    'Let us go!',
    'Respect!',
  ];

  static const emojis = [
    '😀',
    '😂',
    '👍',
    '👎',
    '🙏',
    '🔥',
    '💪',
    '🎯',
    '⏰',
    '😅',
    '🤞',
    '👏',
    '😎',
    '🥳',
    '😤',
    '💯',
    '✨',
    '🎲',
    '🏆',
    '❤️',
    '😮',
    '🤔',
    '🫡',
    '🙌',
    '😇',
    '🤣',
    '⚡',
    '🌟',
    '💀',
    '😴',
  ];

  static int get catalogLength => phrases.length + emojis.length;

  static String messageAt(int index) {
    if (index >= 0 && index < phrases.length) return phrases[index];
    final e = index - phrases.length;
    if (e >= 0 && e < emojis.length) return emojis[e];
    return '';
  }

  static String sanitizeCustom(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return '';
    t = t.replaceAll(RegExp(r'[\x00-\x08\x0B-\x0C\x0E-\x1F]'), '');
    if (t.length > maxCustomLength) {
      t = t.substring(0, maxCustomLength);
    }
    return t;
  }
}
