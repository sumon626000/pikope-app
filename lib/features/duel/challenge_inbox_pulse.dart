/// Lets push/FCM wake the inbox poller so online players see a challenge sooner.
void Function()? triggerChallengeInboxPoll;

void requestChallengeInboxPoll() => triggerChallengeInboxPoll?.call();
