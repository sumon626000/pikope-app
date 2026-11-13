import 'package:flutter/material.dart';

import '../../features/duel/home_portrait_widgets.dart'
    show
        HomeBottomNav,
        HomeNavItem,
        HomeWalletBar,
        PortraitCanvas,
        pcText,
        titleCase;
import '../icon_motion.dart';
import '../widgets.dart';
import 'design_colors.dart';

export '../../features/duel/home_portrait_widgets.dart'
    show
        HomeBottomNav,
        HomeNavItem,
        HomeWalletBar,
        PortraitCanvas,
        pcText,
        titleCase;

/// Pool City page chrome for the portrait screens (everything except the
/// pool tables). Geometry in 1080-wide design units, taken from the
/// reference app: header 150, title bar 100, tabs 110, red back 210×110.

// ------------------------------------------------------------------- page

/// Portrait page: optional player header, then a title bar or a tab strip,
/// the body, and either the red back button or the five-tab bar.
class PcPage extends StatelessWidget {
  const PcPage({
    super.key,
    required this.body,
    this.header,
    this.title,
    this.tabs,
    this.panel = true,
    this.scroll = true,
    this.nav,
    this.onBack,
    this.bottomTrailing,
    this.bodyPadding = const EdgeInsets.fromLTRB(28, 24, 28, 24),
    this.minHeight = 1700,
  });

  final Widget body;

  /// Avatar, name and wallet across the top (null: just top spacing).
  final PcHeader? header;

  /// Purple title bar under the header.
  final String? title;

  /// Tab strip under the header (instead of, or above, the title).
  final PcTabs? tabs;

  /// Draw the body on the translucent panel.
  final bool panel;

  /// Wrap the body in a vertical scroll view.
  final bool scroll;

  /// Five-tab bar at the bottom (Shop / Inventory style pages).
  final List<HomeNavItem>? nav;

  /// Red back button bottom-left (pushed pages). Ignored when [nav] is set.
  final VoidCallback? onBack;

  /// Widgets right of the back button (info / stats buttons in the reference).
  final Widget? bottomTrailing;
  final EdgeInsets bodyPadding;
  final double minHeight;

  @override
  Widget build(BuildContext context) => PortraitCanvas(
    minHeight: minHeight,
    builder: (context, height) {
      Widget content = Padding(padding: bodyPadding, child: body);
      if (scroll) content = SingleChildScrollView(child: content);
      if (panel) {
        content = Container(
          margin: const EdgeInsets.symmetric(horizontal: 18),
          decoration: pcPanelDecoration(),
          clipBehavior: Clip.antiAlias,
          child: content,
        );
      }
      return Column(
        children: [
          if (header != null) ...[
            const SizedBox(height: 40),
            header!,
          ] else
            const SizedBox(height: 60),
          if (tabs != null) ...[const SizedBox(height: 30), tabs!],
          if (title != null) ...[
            SizedBox(height: tabs == null ? 40 : 20),
            PcTitleBar(title!),
          ],
          const SizedBox(height: 18),
          Expanded(child: content),
          if (nav != null)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: HomeBottomNav(items: nav!),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(50, 30, 50, 50),
              child: Row(
                children: [
                  PcBackButton(
                    onTap: onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  ?bottomTrailing,
                ],
              ),
            ),
        ],
      );
    },
  );
}

/// Translucent dark-purple panel the reference draws its page content on.
BoxDecoration pcPanelDecoration({double radius = 8, Color? fill}) =>
    BoxDecoration(
      color: fill ?? const Color(0xFF2A1C5E).withValues(alpha: 0.74),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: const Color(0xFF5A4A9C).withValues(alpha: 0.7),
        width: 2,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x88000000),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    );

/// Card-style input decoration for the Shop / wallet forms. Turns a bare
/// underline [TextField] into a filled rounded box matching the balance cards
/// ([Color(0xFF0E1428)] fill, accent-tinted border that brightens on focus).
InputDecoration pcFieldDecoration({
  required String label,
  String? hint,
  required bool phone,
  Color accent = const Color(0xFF7D6AD6),
  Widget? prefixIcon,
  Widget? suffixIcon,
  String counterText = '',
}) {
  final radius = BorderRadius.circular(phone ? 12 : 18);
  final labelStyle = TextStyle(
    color: const Color(0xFF9A9AA8),
    fontWeight: FontWeight.w700,
    fontSize: phone ? 12 : 20,
  );
  return InputDecoration(
    isDense: phone,
    filled: true,
    fillColor: const Color(0xFF0E1428),
    labelText: label,
    hintText: hint,
    counterText: counterText,
    labelStyle: labelStyle,
    floatingLabelStyle: labelStyle.copyWith(
      color: accent,
      fontWeight: FontWeight.w900,
    ),
    hintStyle: labelStyle.copyWith(
      color: const Color(0xFF6A6F86),
      fontWeight: FontWeight.w600,
    ),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    contentPadding: EdgeInsets.symmetric(
      horizontal: phone ? 14 : 24,
      vertical: phone ? 14 : 24,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: accent.withValues(alpha: 0.32), width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: accent.withValues(alpha: 0.95), width: 2),
    ),
    border: OutlineInputBorder(borderRadius: radius),
  );
}

/// Avatar with level star, player name, wallet bar.
class PcHeader extends StatelessWidget {
  const PcHeader({
    super.key,
    required this.avatar,
    required this.name,
    required this.registered,
    required this.level,
    required this.coins,
    required this.gems,
    required this.placeholder,
    required this.onProfile,
    required this.onWallet,
  });

  final String avatar;
  final String name;
  final bool registered;
  final int level;
  final int? coins;
  final int? gems;
  final String placeholder;
  final VoidCallback onProfile;
  final VoidCallback onWallet;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 150,
    child: Row(
      children: [
        const SizedBox(width: 18),
        PressScale(
          onTap: onProfile,
          scale: 0.94,
          child: SizedBox(
            width: 130,
            height: 130,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 8,
                  top: 10,
                  child: Container(
                    width: 116,
                    height: 116,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFBFD4FF),
                        width: 3,
                      ),
                      color: const Color(0xFF2A1C5E),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xAA000000),
                          blurRadius: 12,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: registered
                          ? AvatarImage(avatar, size: 110)
                          : const ColoredBox(
                              color: Color(0xFF1A1240),
                              child: Icon(
                                Icons.person_rounded,
                                color: DesignColors.pcTextDim,
                                size: 76,
                              ),
                            ),
                    ),
                  ),
                ),
                if (registered)
                  Positioned(
                    left: -4,
                    top: -4,
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFF8A4A1E),
                            size: 58,
                          ),
                          const Icon(
                            Icons.star_rounded,
                            color: DesignColors.pcGold,
                            size: 50,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              '$level',
                              style: pcText(
                                level >= 100 ? 16 : 22,
                                color: const Color(0xFF5A2E00),
                                shadow: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            registered ? name : titleCase(placeholder),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: pcText(36),
          ),
        ),
        const SizedBox(width: 12),
        HomeWalletBar(
          coins: coins,
          gems: gems,
          placeholder: placeholder,
          onAdd: onWallet,
        ),
        const SizedBox(width: 18),
      ],
    ),
  );
}

/// Full-width purple bar with the page title ("Game Friends").
class PcTitleBar extends StatelessWidget {
  const PcTitleBar(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Container(
    height: 100,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF7A5FE6), Color(0xFF5A44C8)],
      ),
      border: Border(
        top: BorderSide(color: Colors.white.withValues(alpha: 0.35), width: 2),
        bottom: const BorderSide(color: Color(0xFF2A1C5E), width: 3),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x88000000),
          blurRadius: 14,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Text(titleCase(title), style: pcText(50)),
  );
}

/// Tab strip: the active tab is a lit purple block, the others dark.
class PcTabs extends StatelessWidget {
  const PcTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.badges = const [],
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// Red count badge per tab (0 = none).
  final List<int> badges;

  @override
  Widget build(BuildContext context) => Container(
    height: 112,
    padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
    decoration: BoxDecoration(
      color: const Color(0xFF1E1545).withValues(alpha: 0.8),
      border: Border(
        bottom: BorderSide(
          color: Colors.white.withValues(alpha: 0.18),
          width: 2,
        ),
      ),
    ),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: PressScale(
              onTap: () => onChanged(i),
              scale: 0.97,
              child: Container(
                margin: EdgeInsets.fromLTRB(
                  i == 0 ? 36 : 10,
                  0,
                  i == labels.length - 1 ? 36 : 10,
                  0,
                ),
                decoration: BoxDecoration(
                  gradient: i == index
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF7A5FE6), Color(0xFF5A44C8)],
                        )
                      : const LinearGradient(
                          colors: [Color(0xFF3E3456), Color(0xFF342B4C)],
                        ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(
                        alpha: i == index ? 0.4 : 0.12,
                      ),
                      width: 2,
                    ),
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            titleCase(labels[i]),
                            style: pcText(
                              44,
                              color: i == index
                                  ? Colors.white
                                  : const Color(0xFFB3B4D9),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (i < badges.length && badges[i] > 0)
                      Positioned(
                        right: -8,
                        top: -12,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 44),
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF03A4E),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: Text(
                            '${badges[i]}',
                            style: pcText(26, shadow: false),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Toggle between the Rank / Prize style sub-tabs inside a page.
class PcSubTabs extends StatelessWidget {
  const PcSubTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.width = 780,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 80,
    decoration: BoxDecoration(
      color: const Color(0xFF1E1545).withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: PressScale(
              onTap: () => onChanged(i),
              scale: 0.97,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: i == index
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF7A5FE6), Color(0xFF5A44C8)],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  titleCase(labels[i]),
                  style: pcText(
                    40,
                    color: i == index ? Colors.white : const Color(0xFFB3B4D9),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Red back button of the pushed pages.
class PcBackButton extends StatelessWidget {
  const PcBackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    scale: 0.94,
    child: Container(
      width: 210,
      height: 110,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE8415F), Color(0xFFB01E3B)],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFFF8AA0).withValues(alpha: 0.6),
          width: 2.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: const Icon(
        Icons.arrow_back_ios_new_rounded,
        color: Colors.white,
        size: 60,
        shadows: [
          Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
    ),
  );
}

enum PcButtonStyle { blue, gold, gray, red, green, purple }

/// Maps the lobby's legacy accent colours onto the reference's button roles.
PcButtonStyle pcStyleFor(Color? color) {
  if (color == null ||
      color == DesignColors.duelBlue ||
      color == DesignColors.pcBlueButton)
    return PcButtonStyle.blue;
  if (color == DesignColors.duelGold ||
      color == DesignColors.appGold ||
      color == DesignColors.ludoAccent ||
      color == DesignColors.carromAccent)
    return PcButtonStyle.gold;
  if (color == DesignColors.duelRed || color == DesignColors.appDanger)
    return PcButtonStyle.red;
  if (color == DesignColors.rimLight ||
      color == DesignColors.rim ||
      color == DesignColors.dim)
    return PcButtonStyle.gray;
  if (color == DesignColors.duelPurple) return PcButtonStyle.purple;
  if (color == DesignColors.duelGreen ||
      color == DesignColors.appActive ||
      color == DesignColors.poolEightAccent)
    return PcButtonStyle.green;
  return PcButtonStyle.blue;
}

/// Rectangular gradient button of the reference ("Add Friend", "Create").
class PcButton extends StatelessWidget {
  const PcButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = PcButtonStyle.blue,
    this.width,
    this.height = 96,
    this.fontSize = 40,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final PcButtonStyle style;
  final double? width;
  final double height;
  final double fontSize;
  final IconData? icon;

  static List<Color> colorsOf(PcButtonStyle s) => switch (s) {
    PcButtonStyle.blue => const [Color(0xFF5B97FF), Color(0xFF2457D8)],
    PcButtonStyle.gold => const [Color(0xFFF9C64A), Color(0xFFD08A10)],
    PcButtonStyle.gray => const [Color(0xFF9CA1B8), Color(0xFF5E6380)],
    PcButtonStyle.red => const [Color(0xFFE8415F), Color(0xFFB01E3B)],
    PcButtonStyle.green => const [Color(0xFF4ED86A), Color(0xFF1C9A40)],
    PcButtonStyle.purple => const [Color(0xFF9A6CF5), Color(0xFF5B35C8)],
  };

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(style);
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: PressScale(
        onTap: onPressed,
        enabled: enabled,
        scale: 0.96,
        child: Container(
          width: width,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 0 : 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Color.lerp(
                colors[0],
                Colors.white,
                0.45,
              )!.withValues(alpha: 0.8),
              width: 2.5,
            ),
            boxShadow: [
              const BoxShadow(
                color: Color(0x99000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
              BoxShadow(
                color: colors[1].withValues(alpha: 0.4),
                blurRadius: 16,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null)
                Icon(icon, color: Colors.white, size: fontSize * 1.1),
              if (icon != null && label.isNotEmpty)
                SizedBox(width: fontSize * 0.3),
              if (label.isNotEmpty)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      titleCase(label),
                      maxLines: 1,
                      style: pcText(fontSize),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented ON / OFF control of the reference settings.
class PcSegmented<T> extends StatelessWidget {
  const PcSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.height = 96,
    this.fontSize = 40,
  });

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFF1A1240),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFF3E3456), width: 2),
    ),
    child: Row(
      children: [
        for (final e in options.entries)
          Expanded(
            child: PressScale(
              onTap: () => onChanged(e.key),
              scale: 0.97,
              child: Container(
                alignment: Alignment.center,
                decoration: e.key == value
                    ? BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF5B97FF), Color(0xFF2457D8)],
                        ),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.45),
                          width: 2,
                        ),
                      )
                    : null,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      titleCase(e.value),
                      style: pcText(
                        fontSize,
                        color: e.key == value
                            ? Colors.white
                            : const Color(0xFFB3B4D9),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Section heading inside a page ("Sound & Vibration") with its rule.
class PcSectionTitle extends StatelessWidget {
  const PcSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(titleCase(title), style: pcText(40)),
      const SizedBox(height: 10),
      Container(height: 3, color: Colors.white.withValues(alpha: 0.25)),
    ],
  );
}

/// Purple bar heading a block of cards ("Select Mode", "Bet").
class PcSectionBar extends StatelessWidget {
  const PcSectionBar(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Container(
    height: 84,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFF5A48B8), Color(0xFF4A3AA0)]),
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    child: Text(titleCase(title), style: pcText(42)),
  );
}

/// Selectable card: gold border and a tick in the corner when [selected].
class PcSelectCard extends StatelessWidget {
  const PcSelectCard({
    super.key,
    required this.child,
    required this.selected,
    required this.onTap,
    this.width,
    this.height,
    this.label,
  });

  final Widget child;
  final bool selected;
  final VoidCallback onTap;
  final double? width;
  final double? height;
  final String? label;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    scale: 0.97,
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? DesignColors.pcGold
              : Colors.white.withValues(alpha: 0.35),
          width: selected ? 4 : 2,
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0x88000000),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
          if (selected)
            BoxShadow(
              color: DesignColors.pcGold.withValues(alpha: 0.45),
              blurRadius: 18,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(selected ? 4 : 6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (label != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 18,
                child: Text(
                  titleCase(label!),
                  textAlign: TextAlign.center,
                  style: pcText(40),
                ),
              ),
            if (selected)
              Positioned(
                left: 0,
                top: 0,
                child: CustomPaint(
                  size: const Size(90, 90),
                  painter: _CornerTickPainter(),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _CornerTickPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = DesignColors.pcGold,
    );
    final tick = Path()
      ..moveTo(size.width * 0.14, size.height * 0.3)
      ..lineTo(size.width * 0.3, size.height * 0.46)
      ..lineTo(size.width * 0.56, size.height * 0.14);
    canvas.drawPath(
      tick,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.09
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF6E3B14),
    );
  }

  @override
  bool shouldRepaint(_CornerTickPainter old) => false;
}

/// Ranking-style list row: purple slab, light rim; [me] lit, top three tinted.
class PcListRow extends StatelessWidget {
  const PcListRow({
    super.key,
    required this.child,
    this.me = false,
    this.rank,
    this.height = 128,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  final Widget child;
  final bool me;
  final int? rank;
  final double height;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final medal = rank == 1
        ? const Color(0xFFE2B54A)
        : rank == 2
        ? const Color(0xFFC9D0DC)
        : rank == 3
        ? const Color(0xFFD08A5A)
        : null;
    // height 0: size to the child (multi-line cards).
    final row = Container(
      height: height <= 0 ? null : height,
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: me
              ? const [Color(0xFF8A4FD0), Color(0xFF6A35B8)]
              : medal != null
              ? [
                  medal.withValues(alpha: 0.42),
                  const Color(0xFF442F85),
                  const Color(0xFF442F85),
                ]
              : const [Color(0xFF4A3590), Color(0xFF442F85)],
          stops: medal != null && !me ? const [0, 0.55, 1] : null,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: me
              ? const Color(0xFFD9B8FF)
              : const Color(0xFF7D6AD6).withValues(alpha: 0.6),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
    return onTap == null
        ? row
        : PressScale(onTap: onTap, scale: 0.98, child: row);
  }
}

/// Medal disc for ranks 1–3, plain number otherwise.
class PcRankBadge extends StatelessWidget {
  const PcRankBadge(this.rank, {super.key, this.size = 90});

  final int rank;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (rank > 3) {
      return SizedBox(
        width: size,
        child: Text(
          '$rank',
          textAlign: TextAlign.center,
          style: pcText(size * 0.5),
        ),
      );
    }
    final colors = switch (rank) {
      1 => const [Color(0xFFFFE28A), Color(0xFFC98A12)],
      2 => const [Color(0xFFF2F4F8), Color(0xFF8E97A8)],
      _ => const [Color(0xFFF0B07A), Color(0xFF9C5A26)],
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(color: colors[1], width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x88000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        '$rank',
        style: pcText(
          size * 0.5,
          color: colors[1],
          shadow: false,
        ).copyWith(fontStyle: FontStyle.italic),
      ),
    );
  }
}

/// Grey 8-ball with speed lines and a line of text (empty lists, no mail).
class PcEmptyState extends StatelessWidget {
  const PcEmptyState({super.key, required this.message, this.size = 420});

  final String message;
  final double size;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: size,
        height: size * 0.62,
        child: CustomPaint(painter: _EightBallArtPainter()),
      ),
      const SizedBox(height: 40),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 60),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: pcText(
            44,
            color: const Color(0xFFB9B0E8),
          ).copyWith(height: 1.3),
        ),
      ),
    ],
  );
}

class _EightBallArtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = const Color(0xFF8E85C8).withValues(alpha: 0.55);
    final c = Offset(w * 0.3, h * 0.55);
    final r = h * 0.38;
    canvas.drawCircle(c, r, paint);
    canvas.drawCircle(
      Offset(c.dx - r * 0.1, c.dy - r * 0.08),
      r * 0.46,
      Paint()..color = const Color(0xFF2E2564),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: '8',
        style: pcText(
          r * 0.62,
          color: const Color(0xFF8E85C8).withValues(alpha: 0.9),
          shadow: false,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(c.dx - r * 0.1 - tp.width / 2, c.dy - r * 0.08 - tp.height / 2),
    );
    // Speed lines and the cue tip with chalk dust.
    final line = Paint()
      ..color = paint.color
      ..strokeWidth = h * 0.05
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = c.dy + r * (0.15 + i * 0.3);
      canvas.drawLine(
        Offset(c.dx + r * 1.15, y),
        Offset(w * (0.98 - i * 0.08), y),
        line,
      );
    }
    canvas.drawLine(
      Offset(c.dx - r * 1.1, c.dy + r * 1.22),
      Offset(c.dx + r * 1.6, c.dy + r * 1.22),
      line..strokeWidth = h * 0.03,
    );
    canvas.save();
    canvas.translate(c.dx + r * 0.95, c.dy - r * 0.95);
    canvas.rotate(-0.6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, -h * 0.06, w * 0.22, h * 0.12),
        Radius.circular(h * 0.06),
      ),
      paint,
    );
    canvas.restore();
    for (var i = 0; i < 12; i++) {
      final a = -1.2 + i * 0.12;
      final d = r * (1.05 + (i % 3) * 0.12);
      canvas.drawCircle(
        c +
            Offset(
              d *
                  1.02 *
                  (i.isEven ? 1 : 0.9) *
                  (0.6 + 0.4 * (i % 4) / 3) *
                  1.0 *
                  (1),
              0,
            ).scale(1, 1) +
            Offset(0, -d * 0.6 + a * 10),
        h * 0.012 + (i % 3) * h * 0.006,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EightBallArtPainter old) => false;
}

// ----------------------------------------------------------------- dialog

/// Purple modal of the reference: lit header bar with the title and an X,
/// dark body, optional action row. Laid out in 1080-wide design units.
class PcDialog extends StatelessWidget {
  const PcDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = 990,
    this.onClose,
    this.scroll = true,
    this.maxBodyHeight = 1500,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final VoidCallback? onClose;
  final bool scroll;
  final double maxBodyHeight;

  @override
  Widget build(BuildContext context) {
    Widget body = Padding(
      padding: const EdgeInsets.fromLTRB(60, 40, 60, 40),
      child: child,
    );
    if (scroll) body = SingleChildScrollView(child: body);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3A2A7A), Color(0xFF2E2564), Color(0xFF3A2A7A)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF8C7CE8), width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0xCC000000),
              blurRadius: 30,
              offset: Offset(0, 14),
            ),
            BoxShadow(color: Color(0x668C7CE8), blurRadius: 30),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 110,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF7A5FE6), Color(0xFF5A44C8)],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 120),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(titleCase(title), style: pcText(50)),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    child: PressScale(
                      onTap: onClose ?? () => Navigator.of(context).maybePop(),
                      scale: 0.9,
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 60,
                          shadows: [
                            Shadow(
                              color: Color(0x99000000),
                              blurRadius: 6,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxBodyHeight),
              child: body,
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, 44),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 24),
                      actions[i],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows [PcDialog] (or any widget laid out in 1080 design units) scaled to
/// the screen width, over a dark scrim.
Future<T?> showPcDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  barrierColor: const Color(0xD9000000),
  barrierDismissible: barrierDismissible,
  builder: (context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: EdgeInsets.zero,
    child: LayoutBuilder(
      builder: (context, c) {
        final columnW = PortraitCanvas.dialogColumnWidthFor(c.maxWidth);
        final frameH = c.maxHeight * 0.9;
        final scale = columnW / PortraitCanvas.width;
        final framed = FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: PortraitCanvas.width,
            height: frameH / scale,
            child: Center(child: builder(context)),
          ),
        );
        if (columnW >= c.maxWidth - 0.5) {
          return SizedBox(width: c.maxWidth, height: frameH, child: framed);
        }
        return Align(
          alignment: Alignment.center,
          child: SizedBox(width: columnW, height: frameH, child: framed),
        );
      },
    ),
  ),
);

/// Simple message in the Pool City dialog.
Future<void> showPcMessage(
  BuildContext context, {
  required String title,
  required String body,
  String? okLabel,
}) => showPcDialog<void>(
  context,
  builder: (dialog) => PcDialog(
    title: title,
    actions: [
      PcButton(
        label: okLabel ?? 'OK',
        width: 360,
        onPressed: () => Navigator.of(dialog).pop(),
      ),
    ],
    child: Text(
      body,
      textAlign: TextAlign.center,
      style: pcText(38, weight: FontWeight.w500).copyWith(height: 1.35),
    ),
  ),
);

/// Hosts content that was laid out in phone logical pixels (the shop tabs,
/// the settings cards) on the 1080 canvas: the child gets a phone-sized box
/// and is magnified to fill the width.
class PcLegacyScale extends StatelessWidget {
  const PcLegacyScale({super.key, required this.child, this.factor = 2.5});

  final Widget child;
  final double factor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => SizedBox(
      width: c.maxWidth,
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: c.maxWidth / factor,
          height: c.hasBoundedHeight ? c.maxHeight / factor : null,
          child: child,
        ),
      ),
    ),
  );
}

/// Portrait match canvas (Ludo, Carrom): 1080 wide, as tall as the screen
/// allows, scaled to fit. The screen supplies its own wallpaper behind it.
class PortraitGameCanvas extends StatelessWidget {
  const PortraitGameCanvas({
    super.key,
    required this.builder,
    this.minHeight = 1900,
  });

  static const width = 1080.0;

  final double minHeight;

  /// Receives the canvas height in design units.
  final Widget Function(BuildContext context, double height) builder;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, c) {
        final columnW = PortraitCanvas.columnWidthFor(c.maxWidth);
        final fit = c.maxHeight / (columnW / width);
        final height = fit > minHeight ? fit : minHeight;
        final framed = FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: width,
            height: height,
            child: builder(context, height),
          ),
        );
        return Center(
          child: SizedBox(width: columnW, height: c.maxHeight, child: framed),
        );
      },
    ),
  );
}
