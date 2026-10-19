import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';

/// Mobile number field fixed to Bangladesh (+880 prefix).
class BdPhoneField extends StatelessWidget {
  const BdPhoneField({
    super.key,
    required this.controller,
    this.style,
    this.decoration,
  });

  final TextEditingController controller;
  final TextStyle? style;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: style,
      keyboardType: TextInputType.phone,
      autocorrect: false,
      maxLength: 10,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: (decoration ?? const InputDecoration()).copyWith(
        prefixText: '+880 ',
        prefixStyle: style?.copyWith(color: AppColors.textDim) ??
            const TextStyle(fontFamily: 'sans-serif', fontSize: 26, color: AppColors.textDim),
        counterText: '',
      ),
    );
  }
}
