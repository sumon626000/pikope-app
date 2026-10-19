import '../core/brand.dart';

/// Long-form copy (legal, how-to-play) in EN and BN.
class LocalizedContent {
  const LocalizedContent(this.languageCode);

  final String languageCode;
  bool get isBn => languageCode == 'bn';

  List<(String, String)> get howToPlaySections => isBn ? _howToBn : _howToEn;

  List<String> get privacySections => isBn ? _privacyBn : _privacyEn;
  List<String> get termsSections => isBn ? _termsBn : _termsEn;
  List<String> get conditionsSections => isBn ? _conditionsBn : _conditionsEn;

  String get lastUpdated => isBn ? 'সর্বশেষ আপডেট: অক্টোবর ২০২৬' : 'Last updated: October 2026';

  String legalTitle(String kind) {
    if (!isBn) {
      return switch (kind) {
        'privacy' => 'PRIVACY POLICY',
        'terms' => 'TERMS OF SERVICE',
        'conditions' => 'TERMS & CONDITIONS',
        _ => kind,
      };
    }
    return switch (kind) {
      'privacy' => 'গোপনীয়তা নীতি',
      'terms' => 'সেবার শর্ত',
      'conditions' => 'শর্তাবলী',
      _ => kind,
    };
  }
}

const _howToEn = [
  (
    'BILLIARD POKER',
    '4 players, everyone for themselves. Each player holds 7 poker cards and must pocket the '
        'balls those cards stand for. Finish them all, then declare on your next turn to win.'
  ),
  (
    'THE BREAK',
    'Everybody picks one face-down card. Highest card breaks first: K > Q > J > 10 ... 2 > A '
        '(Ace is always lowest). Ties go by suit: Spades > Hearts > Diamonds > Clubs. The rest '
        'shoot in descending order and play continues clockwise.'
  ),
  (
    'CARDS AND BALLS',
    'Ace = ball 1, 2-10 = balls 2-10, Jack = 11, Queen = 12, King = 13. Suits do not matter. '
        'Duplicate ranks count once: four Aces and three 7s mean you only need balls 1 and 7. '
        'No two players ever hold the same exact card.'
  ),
  (
    'YOUR TURN',
    '1. Tap a card to reveal it - that is the ball you are playing.\n'
        '2. Drag on the table to aim. The cue ball must hit that ball first.\n'
        '3. Pull the power bar down and release to shoot.\n'
        'Pocket your ball and one matching card is shown to everyone and grayed out; you keep '
        'shooting until you miss or foul.'
  ),
  (
    '8-BALL (1 V 1)',
    'After the break the table is open: the first ball you legally pocket makes you Solids '
        '(1-7) or Stripes (9-15). Hit one of your own balls first; pocket one to keep '
        'shooting. When your group is gone, tap a pocket to call it, then pocket the 8 there '
        'to win.'
  ),
  (
    '9-BALL (1 V 1)',
    'Balls 1-9. Always hit the lowest ball on the table first; pocket any ball legally to '
        'keep shooting. Pocket the 9 at any time and you win.'
  ),
  (
    '10-BALL (1 V 1)',
    'Balls 1-10, same lowest-ball-first rule. Legally pocket the 10 to win.'
  ),
  (
    'CARROM',
    '1 v 1. Pocket your nine pieces; cover the red queen; avoid fouls with the striker. First to pocket all nine wins.',
  ),
  (
    'LUDO (2 OR 4 PLAYERS)',
    'Roll the dice on your turn and move a piece by that many steps. Pocket all four pieces into the home column '
        'before your opponents. In a 4-player room everyone plays for themselves; in 2-player it is head to head. '
        'Online staked rooms use the same entry fee and prize as the table you picked.',
  ),
];

const _howToBn = [
  (
    'বিলিয়ার্ড পোকার',
    '৪ খেলোয়াড়, প্রত্যেকে নিজের জন্য। প্রত্যেকের ৭টি পোকার কার্ড; কার্ড অনুযায়ী বল পকেট করতে হবে। '
        'সব শেষ করে পরের নিজের টার্নে ঘোষণা করলে জয়।'
  ),
  (
    'ব্রেক',
    'সবাই একটি উল্টো কার্ড নেয়। সর্বোচ্চ কার্ড প্রথমে ব্রেক করে: K > Q > J … ২ > A (এস সবচেয়ে কম)। '
        'টাই হলে স্যুট: Spades > Hearts > Diamonds > Clubs।'
  ),
  (
    'কার্ড ও বল',
    'Ace = বল ১, ২–১০ = বল ২–১০, Jack = ১১, Queen = ১২, King = ১৩। স্যুট গুরু নয়। '
        'একই র‍্যাঙ্ক একবারই গণনা।'
  ),
  (
    'আপনার টার্ন',
    '১. কার্ড ট্যাপ করে খুলুন — সেটাই আপনার বল।\n'
        '২. টেবিলে টেনে লক্ষ্য করুন; কিউ বল সেটাকেই প্রথমে আঘাত করবে।\n'
        '৩. পাওয়ার বার নিচে টেনে ছাড়ুন।\n'
        'বল পকেট করলে মিলে যাওয়া কার্ড দেখা যায়; মিস বা ফাউল পর্যন্ত আবার শট।'
  ),
  (
    '৮-বল (১ বনাম ১)',
    'ব্রেকের পর টেবিল ওপেন। প্রথম লিগালি পকেট করা বল আপনাকে Solids (১–৭) বা Stripes (৯–১৫) দেয়। '
        'নিজের বল প্রথমে; গ্রুপ শেষে ৮-বল কল করে সেই পকেটে পকেট করলে জয়।'
  ),
  (
    '৯-বল (১ বনাম ১)',
    'বল ১–৯। সবসময় টেবিলের সবচেয়ে ছোট বল প্রথমে আঘাত; লিগালি পকেট করলে টার্ন চলে। ৯ পকেট = জয়।'
  ),
  (
    '১০-বল (১ বনাম ১)',
    'বল ১–১০, একই নিয়ম — সবচেয়ে ছোট বল প্রথমে; ১০ লিগালি পকেট = জয়।'
  ),
  (
    'ক্যারাম',
    '১ বনাম ১। নিজের ৯টি গুটি পকেট; লাল রানী কভার; স্ট্রাইকার ফাউল এড়িয়ে খেলুন। ৯টি আগে = জয়।'
  ),
  (
    'লুডু (২ বা ৪ খেলোয়াড়)',
    'আপনার টার্নে ডাইস রোল করে গুটি এগোান। প্রতিপক্ষের আগে চারটি গুটি হোমে নিয়ে জিতুন। '
        '৪ জনে সবাই নিজের জন্য; ২ জনে ১ বনাম ১। অনলাইন স্টেক রুমে বেছে নেওয়া টেবিলের এন্ট্রি ও প্রাইজ প্রযোজ্য।'
  ),
];

List<String> get _privacyEn => [
      '1. Who we are',
      '${Brand.name} is a mobile game app (Pool, Ludo, Carrom and related modes). '
          'This policy explains what we store when you play online and how we use it.',
      '2. Information we collect',
      'Account: nickname, Bangladesh mobile number if you register, password hash, avatar choice, and a player ID. '
          'Gameplay: match history, coin balance changes, wins and losses, and technical logs (errors, connection). '
          'Device: basic app settings stored on your phone (sound, table skin). We do not sell your personal data.',
      '3. How we use data',
      'To run matches, keep your wallet and rank, prevent cheating and abuse, send password-reset OTPs by SMS to your mobile, '
          'and improve stability. Admin staff may review accounts reported for abuse.',
      '4. Retention',
      'Online account data stays while your account exists. You may ask us to delete an account tied to your mobile number. '
          'Guest accounts on a device may be removed if inactive for a long period.',
      '5. Children',
      '${Brand.name} is intended for players aged 13 and older. We do not knowingly collect data from children under 13.',
      '6. Contact',
      'For privacy requests, contact the operator of your ${Brand.name} server using the support channel listed in the app or store listing.',
    ];

List<String> get _privacyBn => [
      '১. আমরা কে',
      '${Brand.name} একটি মোবাইল গেম (পুল, লুডু, ক্যারাম ইত্যাদি)। অনলাইনে খেললে কী ডেটা রাখি তা এখানে বর্ণিত।',
      '২. যা সংগ্রহ করি',
      'অ্যাকাউন্ট: ডাকনাম, +880 মোবাইল (রেজিস্ট্রেশনে), পাসওয়ার্ড হ্যাশ, অ্যাভাটার, প্লেয়ার আইডি। '
          'গেমপ্লে: ম্যাচ ইতিহাস, কয়েন, জয়/হার, লগ। ডিভাইস: সেটিংস (সাউন্ড, টেবিল)। ডেটা বিক্রি করি না।',
      '৩. ব্যবহার',
      'ম্যাচ চালানো, ওয়ালেট/র‍্যাঙ্ক, প্রতারণা রোধ, SMS OTP, স্থিতিশীলতা। অ্যাডমিন অপব্যবহার রিভিউ করতে পারে।',
      '৪. সংরক্ষণ',
      'অ্যাকাউন্ট থাকা পর্যন্ত ডেটা। মোবাইল নম্বরে tied অ্যাকাউন্ট মুছতে অনুরোধ করতে পারেন। দীর্ঘ নিষ্ক্রিয় অতিথি মুছে যেতে পারে।',
      '৫. শিশু',
      '১৩+ খেলোয়াড়ের জন্য। ১৩-এর নিচে জেনেশুনে ডেটা নিই না।',
      '৬. যোগাযোগ',
      'গোপনীয়তা অনুরোধ: অ্যাপ/স্টোরে দেওয়া সাপোর্ট চ্যানেলে সার্ভার অপারেটরের সাথে যোগাযোগ করুন।',
    ];

List<String> get _termsEn => [
      '1. Acceptance',
      'By installing or using ${Brand.name}, you agree to these Terms of Service and our Privacy Policy. '
          'If you do not agree, do not use the app.',
      '2. The service',
      '${Brand.name} provides skill-based casual games with Pico coin. In the app, 1 Pico coin is shown as equal to 1 BDT for reference; '
          'Pico coin remains in-app currency unless we clearly state a separate cash-out offer. There is no guarantee of uninterrupted service.',
      '3. Your account',
      'You are responsible for activity on your account. One person per account. Do not share passwords. '
          'We may suspend accounts that cheat, harass others, or exploit bugs.',
      '4. Pico coin',
      'Pico coin is used for in-app stakes, shop items and bonuses. Balances can change when you play, buy packs, '
          'or receive admin adjustments. We may change economy settings (stakes, fees, shop packs) with notice when possible.',
      '5. Fair play',
      'Bots, collusion, automated play and tampering with the client are forbidden. We may void matches and adjust balances '
          'to correct abuse.',
      '6. Limitation of liability',
      '${Brand.name} is provided "as is". We are not liable for lost coins due to connectivity issues, device failure, '
          'or force majeure, within limits allowed by law.',
      '7. Changes',
      'We may update these terms. Continued use after an update means you accept the new terms.',
    ];

List<String> get _termsBn => [
      '১. গ্রহণ',
      '${Brand.name} ইনস্টল/ব্যবহার মানে আপনি সেবার শর্ত ও গোপনীয়তা নীতি মেনে নিচ্ছেন। না মানলে অ্যাপ ব্যবহার করবেন না।',
      '২. সেবা',
      'দক্ষতাভিত্তিক ক্যাজুয়াল গেম ও পিকো কয়েন। ১ কয়েন = ১ টাকা শুধু রেফারেন্স; কয়েন ইন-অ্যাপ unless স্পষ্ট ক্যাশ-আউট। '
          'নিরবচ্ছিন্ন সেবার গ্যারান্টি নেই।',
      '৩. অ্যাকাউন্ট',
      'আপনার অ্যাকাউন্টের কাজের দায় আপনার। একজন এক অ্যাকাউন্ট। পাসওয়ার্ড শেয়ার নয়। '
          'চিট, হয়রানি, বাগ অপব্যবহারে সাসপেন্ড করতে পারি।',
      '৪. পিকো কয়েন',
      'স্টেক, শপ, বোনাস। খেলা/প্যাক/অ্যাডমিনে ব্যালেন্স বদল। ইকোনমি সেটিংস নোটিস সহ বদলাতে পারে।',
      '৫. ফেয়ার প্লে',
      'বট, কলুশন, অটো প্লে, ক্লায়েন্ট ট্যামpering নিষিদ্ধ। ম্যাচ বাতিল ও ব্যালেন্স ঠিক করতে পারি।',
      '৬. দায় সীমা',
      '"যেমন আছে" ভিত্তিতে। সংযোগ/ডিভাইস/force majeure-তে হারানো কয়েনের দায় আইনসীমায় নেই।',
      '৭. পরিবর্তন',
      'শর্ত আপডেট হতে পারে। আপডেটের পর ব্যবহার = নতুন শর্ত মেনে নেওয়া।',
    ];

List<String> get _conditionsEn => [
      '1. Scope',
      'These Terms & Conditions apply to all game modes in ${Brand.name}, including practice, friend rooms and staked online tables.',
      '2. Eligibility',
      'You must follow local laws where you play. You must not use the app where skill gaming with virtual stakes is prohibited if that applies to you.',
      '3. Referrals',
      'If you share your player ID, rewards apply only as described in the app. Self-referral and fake accounts are not allowed.',
      '4. Shop and promotions',
      'Coin pack prices, discounts and free packs are set by the operator and may change. Purchases use in-app coins only unless a future update adds another payment method with clear labeling.',
      '5. Content and conduct',
      'Do not use offensive names or images. We may rename, remove avatars or ban users who break community standards.',
      '6. Termination',
      'You may stop using the app at any time. We may terminate access for violations. Unused virtual coins are not convertible to cash.',
      '7. Governing contact',
      'Questions about these conditions: use the same support contact as in the Privacy Policy.',
    ];

List<String> get _conditionsBn => [
      '১. প্রযোজ্যতা',
      'অ্যাপের সব মোডে — অভ্যাস, বন্ধু রুম, স্টেক টেবিল — এই শর্ত প্রযোজ্য।',
      '২. যোগ্যতা',
      'যেখানে খেলেন স্থানীয় আইন মানুন। যেখানে ভার্চুয়াল স্টেক নিষিদ্ধ সেখানে ব্যবহার করবেন না।',
      '৩. রেফার',
      'প্লেয়ার আইডি শেয়ারে পুরস্কার শুধু অ্যাপে বর্ণিতভাবে। নিজেকে রেফার/ফেক অ্যাকাউন্ট নিষিদ্ধ।',
      '৪. শপ',
      'প্যাক/ডিসকাউন্ট অপারেটর সেট করে; বদলাতে পারে। কেনাকাটা ইন-অ্যাপ কয়েন unless অন্য পেমেন্ট স্পষ্ট লেবেলে।',
      '৫. আচরণ',
      'অশ্লীল নাম/ছবি নয়। মান ভাঙলে নাম বদল, অ্যাভাটার সর, ব্যান।',
      '৬. বন্ধ',
      'যেকোনো সময় বন্ধ করতে পারেন। লঙ্ঘনে অ্যাক্সেস বন্ধ। অব্যবহৃত কয়েন ক্যাশে নয়।',
      '৭. যোগাযোগ',
      'প্রশ্ন: গোপনীয়তা নীতির সাপোর্ট চ্যানেল।',
    ];
