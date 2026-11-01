/// 4px base grid for padding and gaps (design coordinates on [DesignLayout.canvasSize]).
abstract final class DesignSpacing {
  static const unit = 4.0;
  static const x1 = unit;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
  static const x12 = 48.0;

  static const screenEdge = 42.0;
  static const navGap = 19.0;
  static const gameCardGap = 20.0;
}

abstract final class DesignRadii {
  static const sm = 10.0;
  static const md = 16.0;
  static const panel = 18.0;
  static const lg = 20.0;
  static const dialog = 22.0;
  static const gameCard = 18.0;
  static const gameCardInner = 15.0;
}

abstract final class DesignElevation {
  static const panelBlur = 20.0;
  static const panelOffsetY = 10.0;
  static const gameCardBlur = 18.0;
}
