import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationUnreadNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int count) => state = count;
}

final notificationUnreadProvider = NotifierProvider<NotificationUnreadNotifier, int>(NotificationUnreadNotifier.new);
