import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Phone-column caps for portrait Pool City on wide desktop / web.
///
/// Shared by [PortraitCanvas], dialog frames, and leftover landscape menu
/// canvases so oversized edge-to-edge UI stays consistent.
abstract final class PortraitWebLayout {
  static const designWidth = 1080.0;

  /// Above this viewport width, use a centered phone column instead of full bleed.
  static const wideBreakpoint = 700.0;

  /// Max logical width of the phone column on desktop / large web.
  static const phoneColumnMaxWidth = 420.0;

  /// Popups on desktop: slightly narrower than the home column.
  static const dialogColumnMaxWidth = 360.0;

  /// Legacy landscape menu canvases (1600×900) on wide desktop.
  static const landscapeMenuMaxWidth = 960.0;
  static const landscapeMenuMaxHeight = 540.0;

  /// Width used to scale the 1080 design canvas for [viewportWidth].
  static double columnWidthFor(double viewportWidth) {
    if (viewportWidth >= wideBreakpoint) {
      return math.min(phoneColumnMaxWidth, viewportWidth);
    }
    return viewportWidth;
  }

  /// Width used to scale dialogs / choosers (tighter on desktop web).
  static double dialogColumnWidthFor(double viewportWidth) {
    if (viewportWidth >= wideBreakpoint) {
      return math.min(dialogColumnMaxWidth, viewportWidth);
    }
    return viewportWidth;
  }

  /// Host box for landscape menu pages; full viewport below the breakpoint.
  static Size landscapeMenuHost(Size viewport) {
    if (viewport.width < wideBreakpoint) return viewport;
    return Size(
      math.min(landscapeMenuMaxWidth, viewport.width),
      math.min(landscapeMenuMaxHeight, viewport.height),
    );
  }
}

/// Canvas, breakpoints, and component dimensions (1600×900 lobby space unless noted).
abstract final class DesignLayout {
  static const canvasSize = Size(1600, 900);

  // --- Responsive breakpoints (logical pixels, after layout / viewport) ---
  static const phoneLandscapeMaxShortSide = 720.0;
  static const phoneLandscapeMinWidth = 640.0;
  static const tabletMinShortSide = 720.0;
  static const desktopMinWidth = 1280.0;

  /// Lobby primary [DuelButton] default.
  static const primaryButtonWidth = 280.0;
  static const primaryButtonHeight = 62.0;
  static const primaryButtonFontSize = 26.0;

  /// Dialogs, auth prompt, settings actions.
  static const compactButtonWidth = 160.0;
  static const compactButtonHeight = 42.0;
  static const compactButtonFontSize = 15.0;

  /// [GameButton] default (PageFrame / login).
  static const formButtonHeight = 64.0;
  static const formButtonFontSize = 20.0;

  /// [GameCard] on home / pool hub.
  static const gameCardWidth = 296.0;
  static const gameCardHeight = 448.0;
  static const gameCardPlayHeight = 54.0;
  static const gameCardPlayFontSize = 22.0;

  /// Bottom nav [NavTile].
  static const navTileSize = 132.0;
  static const navTileIconSize = 58.0;

  /// [DuelTopBar] chrome.
  static const topBarHeight = 112.0;

  /// Dialog width cap in design coords (see [showDuelDialog] scaler).
  static const dialogMaxWidth = 440.0;

  /// Home / hub three-column layout (1600×900 canvas).
  static const homeLeftRailWidth = 178.0;
  static const homeRightRailWidth = 380.0;
  static const homeMainTopInset = 118.0;
  static const homeGameCardsTop = 234.0;

  static const poolHubCardWidth = 240.0;
  static const poolHubCardGap = 16.0;
  static const poolHubContentLeft = 120.0;

  static const bottomBarInset = 34.0;
  static const bottomBarTop = 722.0;
  static const bottomStatusWidth = 248.0;
  static const bottomStatusHeight = 132.0;
}

/// Viewport helpers for adaptive work in Phase 3+.
abstract final class DesignBreakpoints {
  static bool phoneLike(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.shortestSide <= DesignLayout.phoneLandscapeMaxShortSide ||
        size.width < DesignLayout.phoneLandscapeMinWidth;
  }

  static bool tabletOrWider(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >=
      DesignLayout.tabletMinShortSide;

  static bool desktopWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= DesignLayout.desktopMinWidth;

  static bool isLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width >= size.height * 0.98;
  }
}
