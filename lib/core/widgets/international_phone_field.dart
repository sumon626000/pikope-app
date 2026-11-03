import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../phone_countries.dart';

/// Phone field with country flag / dial-code picker (default = device locale country).
class InternationalPhoneField extends StatefulWidget {
  const InternationalPhoneField({
    super.key,
    required this.controller,
    required this.country,
    required this.onCountryChanged,
    this.style,
    this.decoration,
    this.dense = false,
  });

  final TextEditingController controller;
  final PhoneCountry country;
  final ValueChanged<PhoneCountry> onCountryChanged;
  final TextStyle? style;
  final InputDecoration? decoration;
  final bool dense;

  @override
  State<InternationalPhoneField> createState() => _InternationalPhoneFieldState();
}

class _InternationalPhoneFieldState extends State<InternationalPhoneField> {
  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<PhoneCountry>(
      context: context,
      backgroundColor: const Color(0xFF12182C),
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in PhoneCountries.all)
                ListTile(
                  leading: Text(c.flag, style: TextStyle(fontSize: widget.dense ? 22 : 28)),
                  title: Text(
                    c.name,
                    style: TextStyle(
                      fontFamily: 'sans-serif',
                      fontSize: widget.dense ? 15 : 18,
                      color: AppColors.text,
                    ),
                  ),
                  trailing: Text(
                    c.dialDisplay,
                    style: TextStyle(
                      fontFamily: 'sans-serif',
                      fontSize: widget.dense ? 14 : 16,
                      color: AppColors.textDim,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop(c),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) widget.onCountryChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final flagSize = widget.dense ? 20.0 : 26.0;
    final prefix = GestureDetector(
      onTap: _pickCountry,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.only(left: widget.dense ? 4 : 8, right: widget.dense ? 6 : 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.country.flag, style: TextStyle(fontSize: flagSize)),
            const SizedBox(width: 6),
            Text(
              widget.country.dialDisplay,
              style: widget.style?.copyWith(color: AppColors.textDim) ??
                  TextStyle(
                    fontFamily: 'sans-serif',
                    fontSize: widget.dense ? 15 : 22,
                    color: AppColors.textDim,
                  ),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: AppColors.textDim, size: widget.dense ? 22 : 28),
          ],
        ),
      ),
    );

    return TextField(
      controller: widget.controller,
      style: widget.style,
      keyboardType: TextInputType.phone,
      autocorrect: false,
      maxLength: widget.country.nationalMaxLength + 2,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: (widget.decoration ?? const InputDecoration()).copyWith(
        prefixIcon: prefix,
        prefixIconConstraints: BoxConstraints(minWidth: widget.dense ? 108 : 140),
        counterText: '',
      ),
    );
  }
}
