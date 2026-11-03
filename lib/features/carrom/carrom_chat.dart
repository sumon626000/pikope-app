import '../ludo/ludo_chat.dart';

/// Carrom in-match chat catalog (phrases + shared emojis).
abstract final class CarromChat {
  static const maxCustomLength = LudoChat.maxCustomLength;

  static const phrases = [
    'Good luck!',
    'Nice shot!',
    'Well played!',
    'Hurry up!',
    'Thanks!',
    'Sorry!',
    'Oops!',
    'So close!',
    'Great game!',
    'One more round?',
    'Nice break!',
    'Come on!',
    'Unlucky!',
    'Clean pocket!',
    'Watch this!',
    'No way!',
    'Yes!',
    'Please wait',
    'Ready?',
    'Good game',
    'Focus!',
    'Queen time!',
    'Almost there',
    'Not again!',
    'Respect!',
  ];

  static const emojis = LudoChat.emojis;

  static int get catalogLength => phrases.length + emojis.length;

  static String messageAt(int index) {
    if (index >= 0 && index < phrases.length) return phrases[index];
    final e = index - phrases.length;
    if (e >= 0 && e < emojis.length) return emojis[e];
    return '';
  }

  static String sanitizeCustom(String raw) => LudoChat.sanitizeCustom(raw);
}
