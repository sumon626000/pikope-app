import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppUpdateOffer {
  const AppUpdateOffer({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.apkSha256,
    required this.notes,
  });

  final int versionCode;
  final String versionName;
  final Uri url;
  final String apkSha256;
  final String notes;
}

Future<AppUpdateOffer?> peekAppUpdate(WidgetRef ref) async => null;

Future<void> checkForAppUpdate(BuildContext context, WidgetRef ref) async {}

class MandatoryUpdateScreen extends StatelessWidget {
  const MandatoryUpdateScreen({super.key, required this.offer});

  final AppUpdateOffer offer;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
