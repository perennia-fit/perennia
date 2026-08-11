import 'package:flutter/widgets.dart';

import 'design_tokens.g.dart';

class AppDimens {
  AppDimens._();

  static const double base = DesignTokens.spacingBase;
  static const double dense = DesignTokens.spacingDense;
  static const double rowHeight = DesignTokens.rowHeight;
  static const double touchTarget = DesignTokens.touchTarget;
  static const double supersetBar = 4;
}

class AppRadii {
  AppRadii._();

  static const Radius sm = Radius.circular(DesignTokens.radiusSm);
  static const Radius md = Radius.circular(DesignTokens.radiusMd);
  static const Radius full = Radius.circular(DesignTokens.radiusFull);

  static const BorderRadius cardMd = BorderRadius.all(md);
  static const BorderRadius chipFull = BorderRadius.all(full);
}
