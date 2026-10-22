import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_state.dart';
import '../data/app_game.dart';
import '../features/duel/lobby_data.dart';

import 'localized_content.dart';

export 'localized_content.dart';

/// App copy: English (default) and full Bengali.
class AppStrings {
  const AppStrings(this.languageCode);

  static const en = AppStrings('en');

  final String languageCode;
  bool get isBn => languageCode == 'bn';

  String _t(String en, String bn) => isBn ? bn : en;

  // —— Common ——
  String get back => _t('BACK', 'ফিরে');
  String get cancel => _t('CANCEL', 'বাতিল');
  String get ok => _t('OK', 'ঠিক আছে');
  String get copy => _t('COPY', 'কপি');
  String get or => _t('OR', 'অথবা');
  String get loading => _t('LOADING...', 'লোড হচ্ছে...');
  String get submit => _t('SUBMIT', 'জমা দিন');
  String get sending => _t('SENDING...', 'পাঠানো হচ্ছে...');
  String get saving => _t('SAVING...', 'সেভ হচ্ছে...');
  String get offlineServer => _t('CANNOT REACH THE SERVER', 'সার্ভারে যোগাযোগ হচ্ছে না');
  String get notDone => _t('NOT DONE', 'হয়নি');
  String get privacy => _t('PRIVACY', 'গোপনীয়তা');
  String get terms => _t('TERMS', 'শর্তাবলী');
  String get conditions => _t('CONDITIONS', 'শর্ত');

  // —— Language ——
  String get language => _t('LANGUAGE', 'ভাষা');
  String get languageEnglish => _t('English', 'English');
  String get languageBangla => _t('Bangla', 'বাংলা');
  String get languageHint => _t('Choose app language. Default is English.', 'অ্যাপের ভাষা বেছে নিন। ডিফল্ট English।');

  // —— Login / auth ——
  String get taglineGames => _t('POOL  |  LUDO  |  CARROM', 'পুল  |  লুডু  |  ক্যারাম');
  String get taglinePick => _t('PICK YOUR TABLE AND PLAY', 'টেবিল বেছে খেলুন');
  String get signUpOrLogin => _t('SIGN UP OR LOG IN', 'সাইন আপ বা লগ ইন');
  String loginSubtitle(bool hasBackend) => hasBackend
      ? _t(
          'Bangladesh mobile (+880) only. Sign up needs no OTP — only forgot password uses SMS OTP.',
          '+880 মোবাইল। সাইন আপে OTP নেই — শুধু পাসওয়ার্ড ভুলে গেলে SMS OTP।',
        )
      : _t(
          'Mobile sign-up and log in need the game server. Guest play works offline.',
          'মোবাইল সাইন আপ/লগ ইনের জন্য সার্ভার দরকার। অতিথি অফলাইনে খেলতে পারবেন।',
        );
  String get fieldMobile => _t('Mobile number', 'মোবাইল নম্বর');
  String get fieldPassword => _t('Password (6+ for sign up)', 'পাসওয়ার্ড (সাইন আপ ৬+ অক্ষর)');
  String get signupReferralHint => _t('Friend ID / referral (optional)', 'বন্ধুর আইডি / রেফার (ঐচ্ছিক)');
  String get fieldNickname => _t('Nickname (for sign up)', 'ডাকনাম (সাইন আপ)');
  String get fieldInvite => _t('Invite code (optional)', 'ইনভাইট কোড (ঐচ্ছিক)');
  String get logIn => _t('LOG IN', 'লগ ইন');
  String get signUp => _t('SIGN UP', 'সাইন আপ');
  String get forgotPassword => _t('FORGOT PASSWORD?', 'পাসওয়ার্ড ভুলে গেছেন?');
  String get playAsGuest => _t('PLAY AS GUEST', 'অতিথি হিসেবে খেলুন');
  String get enterPassword => _t('Enter your password.', 'পাসওয়ার্ড লিখুন।');
  String get passwordMin8 => _t('Password must be at least 8 characters.', 'পাসওয়ার্ড কমপক্ষে ৮ অক্ষর।');
  String get passwordMin6 => _t('Password must be at least 6 characters.', 'পাসওয়ার্ড কমপক্ষে ৬ অক্ষর।');
  String get referralCodeInvalid => _t('Referral code must be 6 digits, or leave empty.', 'রেফার কোড ৬ সংখ্যা, না থাকলে খালি রাখুন।');
  String get phoneEmpty => _t('Enter your mobile number.', 'মোবাইল নম্বর লিখুন।');
  String get phoneInvalid => _t('Use a valid Bangladesh number (10 digits after +880).', '+880 এর পর ১০ ডিজিটের সঠিক নম্বর দিন।');

  // —— Loading ——
  String get loadingBilliard => _t('BILLIARD  |  BILLIARD POKER', 'বিলিয়ার্ড  |  বিলিয়ার্ড পোকার');

  // —— Top bar / chrome ——
  String get navData => _t('DATA', 'ডেটা');
  String get navNotifications => _t('NOTIFICATIONS', 'নোটিফিকেশন');
  String get notificationsEmpty => _t('Nothing new right now.', 'এখন কিছু নেই।');

  // —— Settings ——
  String get settingsTitle => _t('PROFILE & SETTINGS', 'প্রোফাইল ও সেটিংস');
  String get settingsPrefsBlock => _t('LANGUAGE & GAME', 'ভাষা ও গেম');
  String get sectionPlayer => _t('PLAYER', 'প্লেয়ার');
  String get nicknameLabel => _t('Nickname (3-16: letters, numbers, _)', 'ডাকনাম (৩–১৬: অক্ষর, সংখ্যা, _)');
  String get phoneShown => _t('Mobile number', 'মোবাইল নম্বর');
  String get noPhoneYet => _t('No mobile number yet', 'এখনো মোবাইল নম্বর নেই');
  String get nameEvery7 => _t('You can change your name once every 7 days.', 'নাম ৭ দিনে একবার বদলাতে পারবেন।');
  String nameNextChange(String when) => _t('Next change: $when', 'পরের বদল: $when');
  String get saveName => _t('SAVE NAME', 'নাম সেভ');
  String get nameSaved => _t('Name saved.', 'নাম সেভ হয়েছে।');
  String winsGames(int w, int g) => _t('$w WINS / $g GAMES', '$w জয় / $g গেম');
  String get coinBdtHint => _t('1 Pico coin = 1 BDT', '১ পিকো কয়েন = ১ টাকা');
  String get uploading => _t('UPLOADING...', 'আপলোড...');
  String get uploadPhoto => _t('UPLOAD PHOTO', 'ছবি আপলোড');
  String get uploadNeedsServer =>
      _t('Photo upload needs the game server (or Cloudinary) to be configured.', 'ছবি আপলোডের জন্য সার্ভার সেটআপ দরকার।');
  String get logout => _t('LOG OUT', 'লগ আউট');
  String get logoutConfirmTitle => _t('LOG OUT', 'লগ আউট');
  String get logoutConfirmBody => _t('Sign out of this player on this device?', 'এই ডিভাইস থেকে সাইন আউট করবেন?');
  String get sound => _t('SOUND', 'সাউন্ড');
  String get soundOn => _t('Sound on', 'সাউন্ড চালু');
  String get soundOff => _t('Sound off', 'সাউন্ড বন্ধ');

  // —— Shop ——
  String get picoCoin => _t('PICO COIN', 'পিকো কয়েন');
  String shopSub(int globalDiscount) => globalDiscount > 0
      ? _t('EXTRA $globalDiscount% ON PACKS · 1 COIN = 1 BDT', 'প্যাকে অতিরিক্ত $globalDiscount% · ১ কয়েন = ১ টাকা')
      : _t('PACK BONUS 5%–30% · 1 COIN = 1 BDT', 'প্যাক বোনাস ৫%–৩০% · ১ কয়েন = ১ টাকা');
  String get tabTransfer => _t('COIN TRANSFER', 'কয়েন ট্রান্সফার');
  String get tabBuy => _t('BUY', 'কিনুন');
  String get tabAdd => _t('ADD', 'যোগ');
  String get tabRedeem => _t('REDEEM', 'রিডিম');
  String get tabHistory => _t('HISTORY', 'ইতিহাস');
  String get transferOff => _t('Coin transfer is off.', 'কয়েন পাঠানো বন্ধ।');
  String get transferGameIdLabel => _t('RECIPIENT GAME ID (6 DIGITS)', 'গ্রহীতার গেম আইডি (৬ সংখ্যা)');
  String get transferAmountLabel => _t('AMOUNT (PICO COIN)', 'পরিমাণ (পিকো কয়েন)');
  String transferFeeHint(int pct, String fee, String total) =>
      _t('Fee $pct% ($fee) · Total deducted $total', 'ফি $pct% ($fee) · মোট কাটা $total');
  String get transferConfirmTap => _t('TAP AGAIN TO SEND', 'পাঠাতে আবার ট্যাপ করুন');
  String get transferConfirmTitle => _t('SEND COINS?', 'কয়েন পাঠাবেন?');
  String transferConfirmBody(String name, int amount, int fee, int total) => _t(
        'Send ${formatCoinsDisplay(amount)} to $name?\nFee ${formatCoinsDisplay(fee)} — total ${formatCoinsDisplay(total)} from your wallet.',
        '$name কে ${formatCoinsDisplay(amount)} পাঠাবেন?\nফি ${formatCoinsDisplay(fee)} — মোট ${formatCoinsDisplay(total)} কাটা হবে।',
      );
  String get itemsScreenSub => _t('BOARDS & CUES — BUY WITH PICO COIN', 'বোর্ড ও কিউ — পিকো কয়েনে কিনুন');
  String get transferSendBtn => _t('SEND COIN', 'কয়েন পাঠান');
  String get transferGuestOnly => _t('Only registered accounts can send coin.', 'শুধু রেজিস্টার্ড অ্যাকাউন্ট পাঠাতে পারবে।');
  String get transferInvalidId => _t('No player with this game ID.', 'এই গেম আইডিতে কেউ নেই।');
  String get transferNotEligible => _t('This ID cannot receive transfers (guest or invalid).', 'এই আইডি গ্রহণ করতে পারবে না।');
  String get transferSent => _t('TRANSFER SENT', 'পাঠানো হয়েছে');
  String transferSentBody(String name, int amount) => _t('You sent $amount to $name.', '$name কে $amount পাঠানো হয়েছে।');
  String get badgeTransferSuccess => _t('SUCCESS', 'সফল');
  String transferHistorySuccess(int amount, int fee) =>
      _t('Transfer sent · fee $fee', 'পাঠানো হয়েছে · ফি $fee');
  String transferHistoryReceived(int amount) => _t('Received $amount', '$amount পেয়েছেন');
  String get badgeTransfer => _t('TRANSFER', 'ট্রান্সফার');
  String get redeemCancel => _t('CANCEL', 'বাতিল');
  String get redeemPendingTitle => _t('PENDING REDEEMS', 'অপেক্ষমান রিডিম');
  String get redeemCancelled => _t('Redeem cancelled. Coins returned.', 'রিডিম বাতিল। কয়েন ফেরত।');
  String get packsTitle => _t('PICO COIN PACKS', 'পিকো কয়েন প্যাক');
  String get noPacks => _t('NO PACKS YET — ADD THEM IN ADMIN', 'এখনো প্যাক নেই — অ্যাডমিনে যোগ করুন');
  String get cuesSection => _t('CUES', 'কিউ');
  String get cueShop => _t('CUE SHOP', 'কিউ শপ');
  String cuesToUnlock(int n) => _t('$n CUES TO UNLOCK WITH PICO COIN', 'পিকো কয়েনে $nটি কিউ আনলক');
  String get ownEveryCue => _t('YOU OWN EVERY CUE', 'সব কিউ আপনার');
  String get openShop => _t('OPEN  >', 'খুলুন  >');
  String get poolTableBtn => _t('POOL TABLE', 'পুল টেবিল');
  String get carromTableBtn => _t('CARROM TABLE', 'ক্যারাম টেবিল');
  String get carromGearShopTitle => _t('CARROM STRIKER & PIECES', 'ক্যারাম স্ট্রাইকার ও গুটি');
  String get carromCoinLobbySub => _t('ONLINE FOR PICO COINS — CUSTOMIZE GEAR IN SHOP', 'পিকো কয়েনে অনলাইন — গিয়ার শপ থেকে');
  String get shopItemsSection => _t('TABLES, CUES & GEAR', 'টেবিল, কিউ ও গিয়ার');
  String get ludoBoardBtn => _t('LUDO BOARD', 'লুডো বোর্ড');
  String get freeBoard => _t('FREE', 'ফ্রি');
  String get useBoard => _t('USE', 'ব্যবহার');
  String get selectedBoard => _t('SELECTED', 'নির্বাচিত');
  String copiedNumber(String n) => _t('Copied $n', 'কপি: $n');
  String get manualAddOff => _t('Manual add is off right now.', 'ম্যানুয়াল যোগ বন্ধ আছে।');
  String bdtRange(int min, int max) => _t('Amount $min – $max BDT.', 'পরিমাণ $min – $max টাকা।');
  String get enterTrxId => _t('Enter TrxID from your SMS.', 'SMS এর TrxID লিখুন।');
  String get enterPayerPhone => _t('Enter the number you paid from.', 'যে নম্বর থেকে পেমেন্ট করেছেন লিখুন।');
  String get requestSent => _t('REQUEST SENT', 'অনুরোধ পাঠানো');
  String depositPendingBody(String coins) => _t(
        'Admin will verify TrxID. You get +$coins when approved.',
        'অ্যাডমিন TrxID যাচাই করবে। অনুমোদনে +$coins পাবেন।',
      );
  String get manualAddOffTitle => _t('MANUAL ADD IS OFF', 'ম্যানুয়াল যোগ বন্ধ');
  String get paymentNumbersNotSet => _t('PAYMENT NUMBERS NOT SET', 'পেমেন্ট নম্বর সেট নেই');
  String get addCoinTitle => _t('ADD PICO COIN', 'পিকো কয়েন যোগ');
  String get addCoinSteps =>
      _t('Choose amount · Pay with bKash/Nagad · Coin credits instantly', 'পরিমাণ বেছে নিন · bKash/Nagad দিয়ে পে · কয়েন সাথে সাথে যোগ');
  String get payNow => _t('PAY NOW', 'এখনই পে');
  String get paymentUnavailable => _t('Payment is not available right now.', 'পেমেন্ট এখন চালু নেই।');
  String get addCoinManual => _t('MANUAL', 'ম্যানুয়াল');
  String get addCoinAuto => _t('AUTO (ZiniPay)', 'অটো (ZiniPay)');
  String get autoAddTitle => _t('AUTO ADD COIN', 'অটো কয়েন যোগ');
  String get autoAddSub => _t('Secure ZiniPay checkout', 'নিরাপদ ZiniPay চেকআউট');
  String get autoAddSteps => _t('Choose amount · Pay with bKash/Nagad · Coin credits instantly', 'পরিমাণ বেছে নিন · bKash/Nagad দিয়ে পে · কয়েন সাথে সাথে যোগ');
  String get payWithZiniPay => _t('PAY WITH ZINIPAY', 'ZINIPAY দিয়ে পে');
  String get pleaseWait => _t('PLEASE WAIT…', 'অপেক্ষা করুন…');
  String get autoAddSuccess => _t('PAYMENT OK', 'পেমেন্ট সফল');
  String get autoAddSuccessBody => _t('Pico coin has been added to your wallet.', 'পিকো কয়েন ওয়ালেটে যোগ হয়েছে।');
  String get autoAddPending => _t('PAYMENT PENDING', 'পেমেন্ট অপেক্ষমান');
  String get autoAddWebHint => _t('Complete payment in this window. When done, you return to the app automatically.', 'এই উইন্ডোতে পেমেন্ট শেষ করুন। শেষ হলে অ্যাপে ফিরে আসবেন।');
  String get amountBdt => _t('Amount (BDT)', 'পরিমাণ (টাকা)');
  String youGetCoins(String c) => _t('You get: $c', 'পাবেন: $c');
  String get payerNumber => _t('Your number (sent payment from)', 'আপনার নম্বর (যেখান থেকে পাঠিয়েছেন)');
  String get trxId => _t('TrxID', 'TrxID');
  String get submitForApproval => _t('SUBMIT FOR APPROVAL', 'অনুমোদনের জন্য জমা');
  String get redeemOff => _t('Redeem is off. Try again later.', 'রিডিম বন্ধ। পরে চেষ্টা করুন।');
  String redeemRange(String min, String max) =>
      _t('Enter $min – $max Pico coin.', '$min – $max পিকো কয়েন লিখুন।');
  String get walletNumberInvalid => _t('Enter your wallet number (11 digits).', 'ওয়ালেট নম্বর (১১ ডিজিট) লিখুন।');
  String get redeemSent => _t('REDEEM SENT', 'রিডিম পাঠানো');
  String get notEnoughCoin => _t('NOT ENOUGH PICO COIN', 'পিকো কয়েন কম');
  String get coinAdded => _t('PICO COIN ADDED', 'পিকো কয়েন যোগ');

  // —— History / inbox ——
  String get historyTitle => _t('MATCH & WALLET DATA', 'ম্যাচ ও ওয়ালেট ডেটা');
  String get historySub => _t('YOUR ACTIVITY', 'আপনার কার্যকলাপ');
  String get historyEmpty => _t('NO ACTIVITY YET', 'এখনো কিছু নেই');
  String get historyLoadFail => _t('CANNOT LOAD HISTORY', 'ইতিহাস লোড হয়নি');
  String get noticesTitle => _t('INBOX', 'ইনবক্স');
  String get noticesSub => _t('NEWS AND ANNOUNCEMENTS', 'খবর ও ঘোষণা');
  String get noticesEmpty => _t('NO MESSAGES YET', 'এখনো মেসেজ নেই');
  String get noticesLoadFail => _t('CANNOT LOAD YOUR MESSAGES', 'মেসেজ লোড হয়নি');
  String get notificationsTitle => _t('NOTIFICATIONS', 'নোটিফিকেশন');
  String get notificationsSub => _t('PUSH AND ALERTS', 'পুশ ও সতর্কতা');
  String get notificationsEmptyList => _t('NO NOTIFICATIONS YET', 'এখনো নোটিফিকেশন নেই');
  String get notificationsLoadFail => _t('CANNOT LOAD NOTIFICATIONS', 'নোটিফিকেশন লোড হয়নি');
  String get markAllRead => _t('MARK ALL READ', 'সব পড়া হয়েছে');

  // —— Settings (extra) ——
  String get sectionTable => _t('TABLE', 'টেবিল');
  String get sectionShotClock => _t('SHOT CLOCK', 'শট ক্লক');
  String get sectionBot => _t('BOT LEVEL', 'বট লেভেল');
  String get sectionSupport => _t('SUPPORT', 'সাপোর্ট');
  String get facebookSupport => _t('FACEBOOK', 'ফেসবুক');
  String get telegramSupport => _t('TELEGRAM', 'টেলিগ্রাম');
  String get supportLinkMissing => _t('This support link is not set yet.', 'এই সাপোর্ট লিংক এখনো সেট হয়নি।');
  String get updateTitle => _t('NEW UPDATE', 'নতুন আপডেট');
  String updateBody(String version) => _t('Version $version is downloading.', 'ভার্সন $version নামছে।');
  String get updateReady => _t('READY TO INSTALL', 'ইনস্টলের জন্য তৈরি');
  String get updateInstall => _t('INSTALL', 'ইনস্টল');
  String get updateLater => _t('LATER', 'পরে');
  String get updateRequiredHint =>
      _t('You must install this update to play.', 'খেলতে হলে এই আপডেট ইনস্টল করতে হবে।');
  String get updateFailed => _t('Could not download the update.', 'আপডেট নামেনি।');
  String get updateFailed404 => _t('APK file not found on the server (404). Upload the file to the link in admin.', 'সার্ভারে APK নেই (404)। অ্যাডমিনের লিংকে ফাইল আপলোড করুন।');
  String updateFailedHttp(String code) => _t('Server replied: HTTP $code', 'সার্ভার: HTTP $code');
  String get updateFailedHash => _t('APK hash mismatch. Clear SHA-256 in admin or upload the correct file.', 'APK hash মিলেনি। অ্যাডমিনে SHA-256 খালি করুন বা সঠিক ফাইল দিন।');
  String get updateFailedNotApk => _t('Download was not an APK (wrong link or login page).', 'ডাউনলোড APK নয় (ভুল লিংক বা লগইন পেজ)।');
  String get updateRetry => _t('TRY AGAIN', 'আবার চেষ্টা');
  String get updateAllow => _t('Allow PikoPe to install apps, then tap Install.', 'PikoPe-কে অ্যাপ ইনস্টলের অনুমতি দিন, তারপর ইনস্টল চাপুন।');
  String get sectionLegal => _t('LEGAL', 'আইনি');
  String get sectionAccount => _t('ACCOUNT', 'অ্যাকাউন্ট');
  String get sectionPlayerId => _t('PLAYER ID', 'প্লেয়ার আইডি');
  String get on => _t('ON', 'চালু');
  String get off => _t('OFF', 'বন্ধ');
  String secLabel(int sec) => _t('$sec SEC', '$sec সেক');
  String get botEasy => _t('EASY', 'সহজ');
  String get botNormal => _t('NORMAL', 'মাঝারি');
  String get botHard => _t('HARD', 'কঠিন');
  String get playerIdHint => _t(
        'This 6-digit ID is also your refer code. A friend enters it when they join.',
        '৬ ডিজিটের এই আইডি আপনার রেফার কোড। বন্ধু জয়েন করার সময় দেবে।',
      );
  String referralEarn(int pct) => _t(
        'You earn $pct% of a friend\'s stake when they start an online match.',
        'বন্ধু অনলাইন ম্যাচ শুরু করলে স্টেকের $pct% পাবেন।',
      );
  String invitedCount(int n) => _t('$n invited', '$n জন আমন্ত্রিত');
  String referralTotals(String today, String month, String all) => _t(
        'Today $today  ·  This month $month  ·  All $all Pico coin',
        'আজ $today  ·  এই মাস $month  ·  মোট $all পিকো কয়েন',
      );
  String referralPerson(String name, String earned) =>
      _t('$name  ·  $earned Pico coin', '$name  ·  $earned পিকো কয়েন');
  String get friendIdOptional => _t('Friend\'s player ID (optional)', 'বন্ধুর প্লেয়ার আইডি (ঐচ্ছিক)');
  String get useId => _t('USE ID', 'আইডি ব্যবহার');
  String uploadFailed(Object e) => _t('Upload failed: $e', 'আপলোড ব্যর্থ: $e');

  // —— History stats ——
  String get matchDataTitle => _t('MATCH DATA', 'ম্যাচ ডেটা');
  String get matchDataSub => _t('WINS · COIN BUY · REDEEM · ALL HISTORY', 'জয় · কয়েন · রিডিম · সব ইতিহাস');
  String get statLevel => _t('LEVEL', 'লেভেল');
  String get statRank => _t('RANK', 'র‍্যাঙ্ক');
  String get statMatches => _t('MATCHES', 'ম্যাচ');
  String get statWins => _t('WINS', 'জয়');
  String get statWinRate => _t('WIN RATE', 'জয়ের হার');
  String get openCoinWallet => _t('OPEN COIN WALLET  >', 'কয়েন ওয়ালেট  >');

  // —— Shop (extra) ——
  String get redeemTurnedOff => _t('REDEEM IS TURNED OFF', 'রিডিম বন্ধ');
  String get cashOutTitle => _t('CASH OUT PICO COIN', 'পিকো কয়েন ক্যাশ আউট');
  String get mainBalanceTitle => _t('YOUR MAIN BALANCE', 'আপনার মেইন ব্যালেন্স');
  String get redeemAvailableTitle => _t('YOUR REDEEM AVAILABLE BALANCE', 'রিডিমের জন্য উপলব্ধ ব্যালেন্স');
  String get redeemWinOnlyHint => _t(
        'Only win balance can be cashed out. Deposits and bonuses stay in your main balance for play.',
        'শুধু জয়ের ব্যালেন্স ক্যাশ আউট করা যায়। ডিপোজিট ও বোনাস মেইন ব্যালেন্সে থাকে — খেলার জন্য।',
      );
  String get notEnoughRedeemable => _t(
        'Not enough redeemable balance. Win matches to increase it.',
        'রিডিম ব্যালেন্স কম। ম্যাচ জিতে বাড়ান।',
      );
  String redeemRateHint(int rate) => _t(
        '1 Pico coin = $rate BDT. Coins are held until admin approves.',
        '১ পিকো কয়েন = $rate টাকা। অ্যাডমিন অনুমোদন পর্যন্ত কয়েন ধরে রাখা হয়।',
      );
  String get coinAmountLabel => _t('Pico coin amount', 'পিকো কয়েন পরিমাণ');
  String youReceiveBdt(int bdt) => _t('You receive: $bdt BDT', 'পাবেন: $bdt টাকা');
  String get walletType => _t('Wallet type', 'ওয়ালেট ধরন');
  String get walletNumber => _t('Wallet number', 'ওয়ালেট নম্বর');
  String get submitRedeem => _t('SUBMIT REDEEM REQUEST', 'রিডিম অনুরোধ জমা');
  String redeemSentBody(int bdt) => _t(
        'Admin will review. $bdt BDT to your wallet when approved.',
        'অ্যাডমিন দেখবে। অনুমোদনে $bdt টাকা ওয়ালেটে।',
      );
  String get claimed => _t('CLAIMED', 'নেওয়া হয়েছে');
  String get free => _t('FREE', 'ফ্রি');
  String bonusPercent(int p) => _t('+$p% BONUS', '+$p% বোনাস');

  // —— Activity badges ——
  String get badgeWin => _t('WIN', 'জয়');
  String get badgeLoss => _t('LOSS', 'হার');
  String get badgePractice => _t('PRACTICE', 'অভ্যাস');
  String get badgeMatch => _t('MATCH', 'ম্যাচ');
  String get badgeCoin => _t('COIN', 'কয়েন');
  String balanceLine(String formatted) => _t('Balance $formatted', 'ব্যালেন্স $formatted');
  String get badgeRedeem => _t('REDEEM', 'রিডিম');
  String get badgeAdd => _t('ADD', 'যোগ');
  String statusLabel(String status) {
    if (!isBn) return status.toUpperCase();
    switch (status) {
      case 'approved':
        return 'অনুমোদিত';
      case 'rejected':
        return 'প্রত্যাখ্যাত';
      case 'pending':
        return 'অপেক্ষমান';
      case 'cancelled':
        return 'বাতিল';
      default:
        return status.toUpperCase();
    }
  }

  static String formatCoinsDisplay(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  // —— Home (shortcuts) ——
  String get dailyBonus => _t('DAILY BONUS', 'দৈনিক বোনাস');
  String get rank => _t('RANK', 'র‍্যাঙ্ক');
  String get missions => _t('MISSIONS', 'মিশন');
  String get claimNow => _t('CLAIM NOW', 'নিন');
  String get mission => _t('MISSION', 'মিশন');
  String get matchInProgress => _t('MATCH IN PROGRESS', 'ম্যাচ চলছে');
  String get rejoinMatch => _t('REJOIN YOUR MATCH', 'ম্যাচে ফিরুন');
  String get online => _t('ONLINE', 'অনলাইন');
  String get refer => _t('REFER', 'রেফার');
  String get dailyBonusGrow => _t('COME BACK EVERY DAY - THE REWARD GROWS', 'প্রতিদিন আসুন — পুরস্কার বাড়ে');
  String dayLabel(int d) => _t('DAY $d', 'দিন $d');
  String gemsBonus(int g) => _t('+$g GEMS', '+$g জেম');

  // —— Bet / practice ——
  String get practice => _t('PRACTICE', 'অভ্যাস');
  String get practiceSub => _t('FREE - BOTS OR PASS & PLAY', 'ফ্রি — বট বা পাস অ্যান্ড প্লে');
  String get practiceSubLudo => _t('FREE — VS BOTS', 'ফ্রি — বটের বিপক্ষে');
  String get practiceSubCarrom => _t('FREE — VS BOT', 'ফ্রি — বটের বিপক্ষে');
  String buyIn(int n) => _t('BUY IN: $n', 'বাই ইন: $n');
  String entryFee(int n) => _t('ENTRY: $n', 'এন্ট্রি: $n');
  String stakeAmount(int n) => _t('STAKE $n', 'স্টেক $n');
  String minPrizePlayers(int prize) =>
      _t('MIN PRIZE ${formatCoinsDisplay(prize)}  -  4 PLAYERS', 'ন্যূন. পুরস্কার ${formatCoinsDisplay(prize)}  -  ৪ খেলোয়াড়');
  String get playersOnline => _t('PLAYERS ONLINE', 'খেলোয়াড় অনলাইন');
  String get tapToPlay => _t('TAP TO PLAY', 'খেলতে ট্যাপ');
  String get practiceLong => _t(
        'Free matches on this device: against bots, or passing the phone between friends. No coins are won or lost.',
        'এই ডিভাইসে ফ্রি ম্যাচ: বটের বিপক্ষে, অথবা বন্ধুদের মধ্যে ফোন হাত বদলে। কোনো কয়েন জিত/হার হবে না।',
      );

  // —— Challenge ——
  String get challengeTitle => _t('CHALLENGE!', 'চ্যালেঞ্জ!');
  String challengesYou(String title) => _t('CHALLENGES YOU TO $title', 'আপনাকে $title এ চ্যালেঞ্জ');
  String buyInWin(int buyIn, String prize) =>
      _t('BUY-IN ${formatCoinsDisplay(buyIn)}  -  WIN $prize', 'বাই-ইন ${formatCoinsDisplay(buyIn)}  -  জয় $prize');
  String get friendlyNoStake => _t('FRIENDLY - NO STAKE', 'বন্ধুত্বপূর্ণ — স্টেক নেই');
  String get noPlayersOnline => _t('NO OTHER PLAYERS ONLINE RIGHT NOW', 'এখন অন্য কেউ অনলাইন নেই');
  String get inMatch => _t('IN MATCH', 'ম্যাচে');
  String waitingAccept(String name) =>
      _t('WAITING FOR ${name.toUpperCase()} TO ACCEPT', '${name.toUpperCase()} গ্রহণের অপেক্ষায়');
  String get stake => _t('STAKE', 'স্টেক');
  String get challengePageTitle => _t('CHALLENGE', 'চ্যালেঞ্জ');
  String get challengePageSub => _t('PLAYERS ONLINE NOW - TAP TO CHALLENGE 1 V 1', 'অনলাইন খেলোয়াড় — ১ বনাম ১ চ্যালেঞ্জ');
  String get accept => _t('ACCEPT', 'গ্রহণ');
  String get decline => _t('DECLINE', 'প্রত্যাখ্যান');
  String get challengeBtn => _t('CHALLENGE', 'চ্যালেঞ্জ');
  String get sectionChallenges => _t('1V1 CHALLENGES', '১ বনাম ১ চ্যালেঞ্জ');
  String get challengesOffShort => _t('CHALLENGES OFF', 'চ্যালেঞ্জ বন্ধ');
  String get challengesSettingHint => _t(
        'Choose which games can send you a 1v1 invite while you are online in the app.',
        'অ্যাপে অনলাইন থাকলে কোন গেম থেকে ১ বনাম ১ চ্যালেঞ্জ নেবেন সেটি বেছে নিন।',
      );
  String get challengeReceivePool => _t('Pool challenges', 'পুল চ্যালেঞ্জ');
  String get challengeReceiveLudo => _t('Ludo challenges', 'লুডু চ্যালেঞ্জ');
  String get challengeReceiveCarrom => _t('Carrom challenges', 'ক্যারাম চ্যালেঞ্জ');
  String get challengePickGame => _t('Game mode', 'গেম মোড');
  String get challengePickStake => _t('Pick a buy-in level', 'বাই-ইন লেভেল বেছে নিন');
  String challengeTableLevel(int level) => _t('Table level $level', 'টেবিল লেভেল $level');
  String challengeExpiresSec(int sec) => _t('${sec}s left', '$sec সেকেন্ড বাকি');
  String playerActivityLabel(String game, bool busy) {
    if (busy) return _t('IN MATCH', 'ম্যাচে');
    if (game.isEmpty) return _t('ONLINE', 'অনলাইন');
    return _t('PLAYING ${game.toUpperCase()}', '${game.toUpperCase()} খেলছে');
  }

  // —— Game overlays ——
  String get passDeviceTo => _t('PASS THE DEVICE TO', 'ডিভাইস দিন');
  String get winner => _t('WINNER', 'বিজয়ী');
  String get menu => _t('MENU', 'মেনু');
  String get connectionLost => _t('CONNECTION LOST', 'সংযোগ নেই');
  String get backOnline => _t('BACK ONLINE', 'আবার অনলাইন');

  // —— Home / lobby nav ——
  String get chooseTable => _t('CHOOSE YOUR TABLE', 'টেবিল বেছে নিন');
  String get pickGameDuel => _t('PICK YOUR GAME AND START DUEL', 'গেম বেছে ডুয়েল শুরু');
  String get navHome => _t('HOME', 'হোম');
  String get navShop => _t('SHOP', 'শপ');
  String get navRankings => _t('RANKINGS', 'র‍্যাঙ্কিং');
  String get navItems => _t('ITEMS', 'আইটেম');
  String get navFriends => _t('FRIENDS', 'বন্ধু');
  String get navChallenge => _t('CHALLENGE', 'চ্যালেঞ্জ');
  String get navCues => _t('CUES', 'কিউ');
  String get navClub => _t('CLUB', 'ক্লাব');
  String get navBack => _t('BACK', 'ফিরে');
  String get playNow => _t('PLAY NOW', 'এখন খেলুন');
  String get close => _t('CLOSE', 'বন্ধ');
  String get claim => _t('CLAIM', 'নিন');
  String get offline => _t('OFFLINE', 'অফলাইন');
  String get tryAgain => _t('TRY AGAIN', 'আবার চেষ্টা');
  String get missionsBody => _t(
        'Daily and weekly missions are on the way. Until then, claim your daily bonus and climb the ranks.',
        'দৈনিক/সাপ্তাহিক মিশন আসছে। ততদিন দৈনিক বোনাস নিন আর র‍্যাঙ্ক বাড়ান।',
      );
  String get friendsTitle => _t('PLAY WITH FRIENDS', 'বন্ধুদের সাথে খেলুন');
  String get friendsBody => _t(
        'Pick a table amount, then create a private room or join with a room code. Entry fee applies; winner takes the prize.',
        'টেবিলের পরিমাণ বেছে নিন, তারপর প্রাইভেট রুম বানান বা রুম কোড দিয়ে জয়েন করুন। এন্ট্রি ফি লাগে; বিজয়ী প্রাইজ পায়।',
      );
  String get poolFriendsTitle => _t('POOL WITH FRIENDS', 'বন্ধুদের সাথে পুল');
  String get poolFriendsBody => _t('Pick the table for your private room.', 'প্রাইভেট রুমের টেবিল বেছে নিন।');
  String ludoPlayers(int n) => _t('LUDO ($n PLAYERS)', 'লুডু ($n খেলোয়াড়)');
  String get howToPlayTitle => _t('HOW TO\nPLAY', 'কিভাবে\nখেলবেন');
  String get howToPlaySub => _t('RULES OF EVERY GAME', 'সব গেমের নিয়ম');
  String get practiceFreeTitle => _t('PRACTICE\nFOR FREE', 'ফ্রি\nঅভ্যাস');
  String get practiceFreeSub => _t('PLAY AGAINST BOTS', 'বটের বিপক্ষে খেলুন');
  String get friendsBannerTitle => _t('PLAY WITH\nFRIENDS', 'বন্ধুদের\nসাথে');
  String get friendsBannerSub => _t('PRIVATE ROOM - STAKED', 'প্রাইভেট রুম — স্টেক');
  String friendsStakeLine(String entry, String prize) =>
      _t('Entry $entry  ·  Win $prize  ·  Share the room code', 'এন্ট্রি $entry  ·  জয় $prize  ·  রুম কোড শেয়ার করুন');
  String get poolSub => _t('8, 9 AND 10 BALL\nAND BILLIARD POKER', '৮, ৯, ১০ বল\nও বিলিয়ার্ড পোকার');
  String get ludoSub => _t('2 OR 4 PLAYERS\nROLL AND RACE HOME', '২ বা ৪ খেলোয়াড়\nঘরে পৌঁছান');
  String get carromSub => _t('1 V 1\nPOCKET YOUR NINE', '১ বনাম ১\nনয়টি পকেট');
  String get clubsTitle => _t('CLUBS', 'ক্লাব');
  String get clubsBody => _t('Clubs and club tournaments are coming in a later update.', 'ক্লাব ও টুর্নামেন্ট পরে আসবে।');
  String get friendsNavBody => _t(
        'Open FRIENDS on the home screen to create a private room and share its code.',
        'হোমে FRIENDS খুলে প্রাইভেট রুম বানান ও কোড শেয়ার করুন।',
      );
  String notEnoughTableBody(String need, String have) => _t(
        'This table needs $need and you have $have. Pick a smaller table, collect your daily bonus or visit the shop.',
        'এই টেবিলে $need দরকার, আপনার $have। ছোট টেবিল, দৈনিক বোনাস বা শপ দেখুন।',
      );
  String modeSubtitle(DuelMode mode) {
    if (!isBn) {
      return switch (mode) {
        DuelMode.billiard => 'BILLIARD 1 V 1 - 8, 9 OR 10 BALL AT RANDOM - WINNER TAKES THE PRIZE',
        DuelMode.eight => '8-BALL 1 V 1 - WINNER TAKES THE PRIZE',
        DuelMode.nine => '9-BALL 1 V 1 - WINNER TAKES THE PRIZE',
        DuelMode.ten => '10-BALL 1 V 1 - WINNER TAKES THE PRIZE',
        DuelMode.poker => 'BILLIARD POKER - 4 PLAYERS - THE WHEEL DECIDES THE PRIZE',
        DuelMode.ludo2 => 'LUDO 1 V 1 - WINNER TAKES THE PRIZE',
        DuelMode.ludo4 => 'LUDO - 4 PLAYERS - WINNER TAKES THE PRIZE',
        DuelMode.carrom => 'CARROM 1 V 1 - WINNER TAKES THE PRIZE',
      };
    }
    return switch (mode) {
      DuelMode.billiard => 'বিলিয়ার্ড ১ বনাম ১ — ৮/৯/১০ বল — বিজয়ী পুরস্কার নেয়',
      DuelMode.eight => '৮-বল ১ বনাম ১ — বিজয়ী পুরস্কার নেয়',
      DuelMode.nine => '৯-বল ১ বনাম ১ — বিজয়ী পুরস্কার নেয়',
      DuelMode.ten => '১০-বল ১ বনাম ১ — বিজয়ী পুরস্কার নেয়',
      DuelMode.poker => 'বিলিয়ার্ড পোকার — ৪ খেলোয়াড় — চাকা পুরস্কার ঠিক করে',
      DuelMode.ludo2 => 'লুডু ১ বনাম ১ — বিজয়ী পুরস্কার নেয়',
      DuelMode.ludo4 => 'লুডু — ৪ খেলোয়াড় — বিজয়ী পুরস্কার নেয়',
      DuelMode.carrom => 'ক্যারাম ১ বনাম ১ — বিজয়ী পুরস্কার নেয়',
    };
  }

  String get prize => _t('PRIZE', 'পুরস্কার');
  String get winUpTo => _t('WIN UP TO', 'জিততে পারেন');
  String get vsBots => _t('VS BOTS', 'বনাম বট');
  String get passAndPlay => _t('PASS & PLAY', 'পাস অ্যান্ড প্লে');

  // —— Game titles / taglines ——
  String gameTitleKey(String key) {
    if (key.startsWith('ludo')) return key == 'ludo4' ? ludo4Players : ludoTitle;
    if (key == 'carrom') return carromTitle;
    return switch (key) {
      'poker' => billiardPokerTitle,
      'eight' => eightBallTitle,
      'nine' => nineBallTitle,
      'ten' => tenBallTitle,
      'billiard' => billiardTitle,
      _ => key.toUpperCase(),
    };
  }

  String appGameTitle(AppGame game) => gameTitleKey(game.apiName);

  String appGameTagline(AppGame game) {
    if (!isBn) return game.tagline;
    return switch (game) {
      AppGame.poker => '৪ খেলোয়াড় — কার্ড বল বেছে নেয়',
      AppGame.eightBall => '১ বনাম ১ — SOLIDS বনাম STRIPES',
      AppGame.nineBall => '১ বনাম ১ — ছোট বল আগে, ৯ জয়',
      AppGame.tenBall => '১ বনাম ১ — ছোট বল আগে, ১০ জয়',
    };
  }

  String get billiardTitle => _t('BILLIARD', 'বিলিয়ার্ড');
  String get billiardPokerTitle => _t('BILLIARD POKER', 'বিলিয়ার্ড পোকার');
  String get eightBallTitle => _t('8-BALL', '৮-বল');
  String get nineBallTitle => _t('9-BALL', '৯-বল');
  String get tenBallTitle => _t('10-BALL', '১০-বল');
  String get ludoTitle => _t('LUDO', 'লুডু');
  String get ludo4Players => _t('LUDO (4 PLAYERS)', 'লুডু (৪ খেলোয়াড়)');
  String get carromTitle => _t('CARROM', 'ক্যারাম');
  String get poolTitle => _t('POOL', 'পুল');

  String get rematch => _t('REMATCH', 'আবার খেলুন');
  String get playAgain => _t('PLAY AGAIN', 'আবার খেলুন');
  String get home => _t('HOME', 'হোম');
  String get resume => _t('RESUME', 'চালিয়ে যান');
  String get howToPlay => _t('HOW TO PLAY', 'কিভাবে খেলবেন');
  String get quitMatch => _t('QUIT MATCH', 'ম্যাচ ছাড়ুন');
  String get imReady => _t("I'M READY", 'আমি প্রস্তুত');
  String get exitToHome => _t('EXIT TO HOME', 'হোমে যান');
  String soundOnLabel(bool on) => on ? _t('SOUND: ON', 'সাউন্ড: চালু') : _t('SOUND: OFF', 'সাউন্ড: বন্ধ');
  String get playerCol => _t('PLAYER', 'খেলোয়াড়');
  String get shotsCol => _t('SHOTS', 'শট');
  String get ballsCol => _t('BALLS', 'বল');
  String get foulsCol => _t('FOULS', 'ফাউল');
  String get penaltyCol => _t('PENALTY', 'পেনালটি');
  String get leftCol => _t('LEFT', 'বাকি');
  String get quickChat => _t('QUICK CHAT', 'দ্রুত চ্যাট');
  String get yourColour => _t('YOUR COLOUR', 'আপনার রং');
  String get shoot => _t('SHOOT', 'শুট');
  String get passBack => _t('PASS BACK', 'ফেরত দিন');
  String get declareWinner => _t('DECLARE WINNER', 'বিজয়ী ঘোষণা');
  String get startMatch => _t('START MATCH', 'ম্যাচ শুরু');
  String get vs => _t('VS', 'বনাম');
  String get code => _t('CODE', 'কোড');
  String get emptySeat => _t('EMPTY', 'খালি');
  String get you => _t('YOU', 'আপনি');
  String get connecting => _t('CONNECTING...', 'সংযোগ...');
  String get guestHint => _t('GUEST - ADD A LOGIN TO KEEP YOUR PROGRESS', 'অতিথি — লগইন যোগ করুন প্রগ্রেস রাখতে');
  String get account => _t('ACCOUNT', 'অ্যাকাউন্ট');
  String get problem => _t('PROBLEM', 'সমস্যা');
  String get retry => _t('RETRY', 'আবার');
  String get quickMatch => _t('QUICK MATCH', 'দ্রুত ম্যাচ');
  String get privateRoom => _t('PRIVATE ROOM', 'প্রাইভেট রুম');
  String get publicRoom => _t('PUBLIC ROOM', 'পাবলিক রুম');
  String get join => _t('JOIN', 'জয়েন');
  String get leave => _t('LEAVE', 'ছাড়ুন');
  String get roomCode => _t('Room code', 'রুম কোড');
  String onlineSuffix(String title) => _t('$title - ONLINE', '$title - অনলাইন');
  String roomTitle(String game, String code) => _t('$game - ROOM $code', '$game - রুম $code');
  String waitingPlayers(int n, int seats) => _t('WAITING FOR PLAYERS  $n/$seats', 'খেলোয়াড়ের অপেক্ষা  $n/$seats');
  String get sharePrivateRoom => _t('Share this code. The match starts when the room is full.', 'কোড শেয়ার করুন। রুম পূর্ণ হলে ম্যাচ শুরু।');
  String get publicRoomHint => _t('Anyone using Quick Match can land here. The match starts when the room is full.', 'কুইক ম্যাচ ব্যবহারকারী আসতে পারে। পূর্ণ হলে শুরু।');
  String get taglinePrivateCarrom => _t('1 V 1 - PRIVATE ROOM', '১ বনাম ১ — প্রাইভেট রুম');
  String taglinePrivateLudo(int n) => _t('$n PLAYERS - PRIVATE ROOM', '$n খেলোয়াড় — প্রাইভেট রুম');
  String get keepProgress => _t('KEEP YOUR PROGRESS', 'প্রগ্রেস রাখুন');
  String get signedIn => _t('SIGNED IN', 'সাইন ইন');
  String get guestAccountBody => _t(
        'You are playing as a guest. Add your Bangladesh mobile (+880) and a password to keep '
            'your coins and wins (no OTP for sign-up). Forgot password sends an SMS OTP, then you set a new password.',
        'অতিথি হিসেবে খেলছেন। +880 মোবাইল ও পাসওয়ার্ড দিয়ে কয়েন/জয় রাখুন (সাইন আপে OTP নেই)। '
            'পাসওয়ার্ড ভুলে গেলে SMS OTP, তারপর নতুন পাসওয়ার্ড।',
      );
  String get mobile880 => _t('Mobile (+880)', 'মোবাইল (+880)');
  String get otpSms => _t('OTP from SMS', 'SMS OTP');
  String get newPassword8 => _t('New password (8+ characters)', 'নতুন পাসওয়ার্ড (৮+ অক্ষর)');
  String get password8 => _t('Password (8+ characters)', 'পাসওয়ার্ড (৮+ অক্ষর)');
  String get setNewPassword => _t('SET NEW PASSWORD', 'নতুন পাসওয়ার্ড');
  String get createLogin => _t('CREATE LOGIN', 'লগইন তৈরি');
  String get signIn => _t('SIGN IN', 'সাইন ইন');
  String get forgotPasswordBtn => _t('FORGOT PASSWORD', 'পাসওয়ার্ড ভুলে গেছেন');
  String get signOut => _t('SIGN OUT', 'সাইন আউট');
  String get status => _t('STATUS', 'স্ট্যাটাস');
  String get msgPasswordChanged => _t('Password changed. You are signed in.', 'পাসওয়ার্ড বদল। সাইন ইন হয়েছে।');
  String get msgLoginAdded => _t('Login added to this account.', 'এই অ্যাকাউন্টে লগইন যোগ।');
  String get msgSignedIn => _t('Signed in.', 'সাইন ইন হয়েছে।');
  String get msgOtpSent => _t('If that number has an account, a 6-digit OTP was sent by SMS.', 'অ্যাকাউন্ট থাকলে ৬ ডিজিট OTP SMS-এ গেছে।');
  String get leaderboard => _t('LEADERBOARD', 'লিডারবোর্ড');
  String get referTitle => _t('REFER', 'রেফার');
  String get referSub => _t('YOUR PLAYER ID IS YOUR REFER CODE', 'প্লেয়ার আইডি = রেফার কোড');
  String get referNeedServer => _t('Player ID is available when the app is connected to the game server.', 'গেম সার্ভারে সংযুক্ত থাকলে প্লেয়ার আইডি পাবেন।');
  String get referLoadFail => _t('Could not load your player ID.', 'প্লেয়ার আইডি লোড হয়নি।');
  String get referFriendId6 => _t('A friend\'s player ID is 6 digits.', 'বন্ধুর প্লেয়ার আইডি ৬ ডিজিট।');
  String get leaderboardEmpty => _t('NO MATCHES PLAYED YET', 'এখনো ম্যাচ খেলেননি');
  String get leaderboardDemo => _t('DEMO DATA - THIS BUILD HAS NO GAME SERVER', 'ডেমো ডেটা — সার্ভার নেই');
  String get playerId => _t('PLAYER ID', 'প্লেয়ার আইডি');
  String get noFriendsReferYet => _t('NO FRIENDS HAVE USED YOUR ID YET', 'এখনো কেউ আপনার আইডি ব্যবহার করেনি');
  String get inUse => _t('IN USE', 'ব্যবহারে');
  String get tablesProfile => _t('TABLES & PROFILE', 'টেবিল ও প্রোফাইল');
  String get chooseTableLook => _t('CHOOSE YOUR TABLE LOOK', 'টেবিল লুক বেছে নিন');
  String buyCue(String name) => _t('BUY ${name.toUpperCase()}?', '${name.toUpperCase()} কিনবেন?');
  String get buy => _t('BUY', 'কিনুন');
  String get myCues => _t('MY CUES', 'আমার কিউ');
  String get practiceFreeBtn => _t('PRACTICE (FREE)', 'অভ্যাস (ফ্রি)');
  String get playForCoin => _t('PLAY FOR PICO COIN', 'পিকো কয়েনে খেলুন');
  String get yourStriker => _t('YOUR STRIKER', 'আপনার স্ট্রাইকার');
  String get yourPieces => _t('YOUR PIECES', 'আপনার গুটি');
  String get yourBoard => _t('YOUR BOARD', 'আপনার বোর্ড');
  String get quickDuel => _t('QUICK\nDUEL', 'দ্রুত\nডুয়েল');
  String jackpotUpTo(String n) => _t('JACKPOT\nUP TO x$n', 'জ্যাকপট\nx$n পর্যন্ত');
  String get matchSetup => _t('MATCH SETUP', 'ম্যাচ সেটআপ');
  String matchSetupGame(String title) => _t('$title - MATCH SETUP', '$title - ম্যাচ সেটআপ');
  String get prizePool => _t('PRIZE POOL', 'পুরস্কার পুল');
  String prizePoolMult(String m) => _t('PRIZE POOL  x$m', 'পুরস্কার পুল  x$m');
  String get buyInHeld => _t('YOUR BUY-IN IS TAKEN ONLY WHEN THE MATCH STARTS', 'ম্যাচ শুরু হলে বাই-ইন কাটা হয়');
  String get lvl => _t('LV', 'লেভ');
  String lvDot(int n) => _t('LV. $n', 'লেভ. $n');
  String lvlBadge(int n) => _t('Lvl $n', 'লেভ $n');
  String lvlUpper(int n) => _t('LVL $n', 'লেভ $n');
  String get yourBalls => _t('YOUR BALLS', 'আপনার বল');
  String get freeBall => _t('FREE', 'ফ্রি');
  String get pull => _t('PULL', 'টানুন');
  String get down => _t('DOWN', 'নিচে');
  String get toShoot => _t('TO', '');
  String get shootLabel => _t('SHOOT', 'শুট');
  String winnerGame(String game) => _t('$game WINNER', '$game বিজয়ী');
  String lowestFirstWins(int n) => _t('LOWEST FIRST - $n WINS', 'ছোট আগে — $n জয়');
  String get gotIt => _t('GOT IT', 'ঠিক আছে');
  String get demoBuild => _t('DEMO BUILD', 'ডেমো বিল্ড');
  String get chooseGame => _t('CHOOSE A GAME', 'গেম বেছে নিন');
  String get onlineMatch => _t('ONLINE MATCH', 'অনলাইন ম্যাচ');
  String get profileTables => _t('PROFILE & TABLES', 'প্রোফাইল ও টেবিল');
  String get practiceTitle => _t('PRACTICE FOR FREE', 'ফ্রি অভ্যাস');
  String get practiceChooserBody => _t(
        'Free matches against bots on this device. No coins are won or lost.',
        'এই ডিভাইসে বটের বিপক্ষে ফ্রি ম্যাচ। কোনো কয়েন জিত/হার নেই।',
      );

  // —— Create profile ——
  String get createProfileTitle => _t('CREATE A PROFILE', 'প্রোফাইল তৈরি');
  String get createProfileSub => _t('SELECT AN AVATAR AND USERNAME', 'অ্যাভাটার ও ইউজারনেম');
  String get usernameHint => _t('USERNAME', 'ইউজারনেম');
  String get randomNameTip => _t('Random name', 'র‍্যান্ডম নাম');
  String get avoidRealName => _t('*Please avoid using real name', '*আসল নাম ব্যবহার করবেন না');
  String get nicknameRulesError => _t('USE 3-16 LETTERS, NUMBERS OR _ (NO SPACES)', '৩–১৬ অক্ষর, সংখ্যা বা _ (স্পেস নয়)');

  // —— Refer (screen) ——
  String get copied => _t('COPIED', 'কপি হয়েছে');
  String referFriendsEarnPct(int pct) => _t(
        'Friends enter this same 6-digit ID. You earn $pct% of their stake when they start an online match.',
        'বন্ধুরা এই ৬ ডিজিট আইডি দেবে। অনলাইন ম্যাচে $pct% পাবেন।',
      );
  String get statInvited => _t('INVITED', 'আমন্ত্রিত');
  String get statToday => _t('TODAY', 'আজ');
  String get statThisMonth => _t('THIS MONTH', 'এই মাস');
  String get statTotal => _t('TOTAL', 'মোট');

  // —— Pool hub ——
  String get poolHubTitle => _t('POOL', 'পুল');
  String get poolHubSub => _t('PICK YOUR TABLE - 1 V 1, OR BILLIARD POKER WITH FOUR', 'টেবিল বেছে নিন — ১ বনাম ১, বা ৪ জন পোকার');
  String get eightBallSubShort => _t('SOLIDS VS STRIPES\nSINK THE 8 LAST', 'SOLIDS বনাম STRIPES\n৮ শেষে');
  String get nineBallSubShort => _t('LOWEST BALL FIRST\n9 WINS', 'ছোট বল আগে\n৯ জয়');
  String get tenBallSubShort => _t('LOWEST BALL FIRST\n10 WINS', 'ছোট বল আগে\n১০ জয়');
  String get billiardPokerCardTitle => _t('BILLIARD\nPOKER', 'বিলিয়ার্ড\nপোকার');
  String get jackpotSubLine => _t('BILLIARD POKER PRIZE WHEEL', 'বিলিয়ার্ড পোকার পুরস্কার চাকা');
  String get quickDuelSubRandom => _t('8, 9 OR 10 BALL AT RANDOM', '৮, ৯ বা ১০ বল র‍্যান্ডম');
  String get practiceBannerSubPass => _t('BOTS OR PASS AND PLAY', 'বট বা পাস অ্যান্ড প্লে');

  // —— Cues ——
  String get myItems => _t('MY ITEMS', 'আমার আইটেম');
  String get cuesSubOwned => _t('YOUR CUES - TAP ONE TO USE IT', 'আপনার কিউ — ব্যবহারে ট্যাপ');
  String get cuesSubBuy => _t('SAME POWER ON ALL CUES - DIFFERENT LOOKS ONLY', 'সব কিউতে একই পাওয়ার — শুধু ডিজাইন আলাদা');
  String get cuesSamePlayHint =>
      _t('Every cue hits the same. Only the body design changes.', 'সব কিউ একই — শুধু বডির ডিজাইন আলাদা।');
  String get notEnoughCueBody => _t('Win matches and collect your daily bonus to afford this cue.', 'ম্যাচ জিতুন ও দৈনিক বোনাস নিন।');
  String get useCue => _t('USE', 'ব্যবহার');
  String get shopTitleShort => _t('SHOP', 'শপ');

  // —— Matchmaking ——
  String get matchFound => _t('MATCH FOUND', 'ম্যাচ মিলেছে');
  String get matchmaking => _t('MATCHMAKING', 'ম্যাচ খোঁজা');

  // —— Challenge send ——
  String get waitingShort => _t('WAITING...', 'অপেক্ষা...');
  String challengePlayer(String name) => _t('CHALLENGE ${name.toUpperCase()}', 'চ্যালেঞ্জ ${name.toUpperCase()}');
  String get notAcceptedTryLater => _t('NOT ACCEPTED - TRY AGAIN LATER', 'গ্রহণ হয়নি — পরে চেষ্টা');
  String get send => _t('SEND', 'পাঠান');
  String get freeStake => _t('FREE', 'ফ্রি');

  // —— Ludo / Carrom lobby ——
  String get ludoLobbySub => _t('PICK PLAYERS AND YOUR COLOUR', 'খেলোয়াড় ও রং বেছে নিন');
  String get twoPlayers => _t('2 PLAYERS', '২ খেলোয়াড়');
  String get fourPlayers => _t('4 PLAYERS', '৪ খেলোয়াড়');
  String ludoColorName(int i) => _t(['RED', 'GREEN', 'YELLOW', 'BLUE'][i], ['লাল', 'সবুজ', 'হলুদ', 'নীল'][i]);
  String get carromLobbySub => _t('1 V 1 - POCKET YOUR NINE PIECES, COVER THE QUEEN', '১ বনাম ১ — ৯ গুটি, রানী কভার');

  // —— HUD ——
  String get pullDownToShoot => _t('PULL DOWN TO SHOOT', 'শুট করতে নিচে টানুন');
  String yourBallsCount(int done, int total) => _t('YOUR BALLS  $done/$total', 'আপনার বল  $done/$total');

  // —— Lobby (practice) ——
  String get botLevelLabel => _t('BOT LEVEL', 'বট লেভেল');
  String get shotClockLabel => _t('SHOT CLOCK', 'শট ক্লক');
  String get humanSeat => _t('HUMAN', 'মানুষ');
  String get botSeat => _t('BOT', 'বট');
  String get twoPlayersOneVsOne => _t('2 PLAYERS - 1 V 1', '২ খেলোয়াড় — ১ বনাম ১');
  String get fourPlayersFreeForAll => _t('4 PLAYERS - FREE FOR ALL', '৪ খেলোয়াড় — সবার বিপক্ষে');
  String playerNumber(int n) => _t('PLAYER $n', 'খেলোয়াড় $n');

  // —— Matchmaking / reveal ——
  String get drawingTheGame => _t('DRAWING THE GAME...', 'গেম নির্বাচন...');
  String nBallLabel(int n) => _t('$n-BALL', '$n-বল');
  String get lookingForOpponent => _t('LOOKING...', 'খোঁজা...');
  String prizeColon(String amount) => _t('PRIZE: $amount', 'পুরস্কার: $amount');
  String buyInColon(String amount) => _t('BUY IN: $amount', 'বাই ইন: $amount');
  String buyInWinUpTo(String buyIn, String maxPrize) =>
      _t('BUY IN: $buyIn  -  WIN UP TO $maxPrize', 'বাই ইন: $buyIn  -  জিততে পারেন $maxPrize');
  String entryWinUpTo(String entry, String maxPrize) =>
      _t('ENTRY: $entry  -  WIN UP TO $maxPrize', 'এন্ট্রি: $entry  -  জিততে পারেন $maxPrize');
  String get readyShort => _t('READY', 'প্রস্তুত');
  String get winBadge => _t('WIN', 'জয়');
  String playerWins(String name) => _t('${name.toUpperCase()} WINS!', '${name.toUpperCase()} জিতেছে!');
  String winningPrize(String amount) => _t('WINNING PRIZE: $amount', 'জয়ের পুরস্কার: $amount');
  String get practiceFriendlyNoCoin => _t('PRACTICE / FRIENDLY — NO PICO COIN', 'অভ্যাস / বন্ধুত্ব — কোনো পিকো কয়েন নেই');
  String youWonAmount(String amount) => _t('YOU WON $amount', 'আপনি জিতেছেন $amount');
  String get betterLuckNext => _t('BETTER LUCK NEXT TIME', 'পরের বার ভালো হবে');

  String reconnectingDots(int n) => _t('RECONNECTING${'.' * n}', 'পুনঃসংযোগ${'.' * n}');
  String get connectionLostBody => _t(
        'CHECK YOUR INTERNET. YOUR SEAT IS SAVED.\nTHE MATCH CONTINUES AS SOON AS YOU ARE BACK.',
        'ইন্টারনেট দেখুন। আপনার সিট সেভ আছে।\nফিরে এলেই ম্যাচ চলবে।',
      );
  String get shotClockExitHint => _t(
        'THE SHOT CLOCK KEEPS RUNNING.\nIF YOU EXIT, REJOIN FROM THE HOME SCREEN.',
        'শট ক্লক চলতে থাকে।\nবের হলে হোম থেকে আবার জয়েন করুন।',
      );

  /// In-game banner / status lines (controllers emit English keys).
  String bannerLine(String line) {
    if (!isBn) return line;
    final exact = _bannerExact[line];
    if (exact != null) return exact;
    if (line.startsWith('NEXT: ')) return 'পরবর্তী: ${line.substring(6)}';
    if (line.endsWith(' BREAKS')) {
      return '${line.substring(0, line.length - 7)} ব্রেক';
    }
    if (line.startsWith('TURN OVER')) return 'টার্ন শেষ';
    if (line.startsWith('PUSH OUT')) return line.replaceFirst('PUSH OUT', 'পুশ আউট').replaceFirst(': SHOOT OR PASS IT BACK', ': শুট বা ফেরত');
    if (line.startsWith('+') && line.contains('EXTRA SHOT')) return line.replaceFirst('EXTRA SHOT', 'অতিরিক্ত শট');
    if (line.contains('FREE BALL POCKETED')) return line.replaceFirst('FREE BALL POCKETED', 'ফ্রি বল পকেট');
    if (line.startsWith('CALL A POCKET')) return 'পকেট কল করুন';
    if (line.contains('TAP THE POCKET')) return '৮-বলের পকেট ট্যাপ করুন';
    if (line.startsWith('PICK YOUR BALL')) return 'প্রথমে বল বেছে নিন';
    if (line.contains('TAP ONE OF YOUR CARDS')) return 'কার্ড ট্যাপ করুন';
    for (final g in AppGame.values) {
      if (line.startsWith(g.title)) return line.replaceFirst(g.title, appGameTitle(g));
    }
    return line;
  }

  static const _bannerExact = {
    'BREAK': 'ব্রেক',
    'MISS': 'মিস',
    'WINNER': 'বিজয়ী',
    'FOUL': 'ফাউল',
    'TURN OVER': 'টার্ন শেষ',
  };

  /// Best-effort translation for common API English messages.
  String maybeApi(String message) {
    if (!isBn) return message;
    final m = message.toLowerCase();
    if (m.contains('not enough')) return 'পর্যাপ্ত পিকো কয়েন নেই।';
    if (m.contains('offline') || m.contains('server')) return 'সার্ভারে যোগাযোগ হচ্ছে না।';
    if (m.contains('password')) return message;
    if (m.contains('trx')) return 'TrxID ইতিমধ্যে ব্যবহার হয়েছে বা ভুল।';
    if (m.contains('pending')) return 'অপেক্ষমান অনুরোধ আছে — একটু অপেক্ষা করুন।';
    return message;
  }
}

final stringsProvider = Provider<AppStrings>((ref) {
  final code = ref.watch(settingsProvider).languageCode;
  return AppStrings(code == 'bn' ? 'bn' : 'en');
});

final localizedContentProvider = Provider<LocalizedContent>((ref) {
  final code = ref.watch(settingsProvider).languageCode;
  return LocalizedContent(code == 'bn' ? 'bn' : 'en');
});
