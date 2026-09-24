import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Original illustration used by the Android listening room and player.
class ImmersiveSceneBackground extends StatelessWidget {
  final Widget child;
  final bool preserveWholeScene;
  final bool backdropOnly;

  const ImmersiveSceneBackground({
    super.key,
    required this.child,
    this.preserveWholeScene = false,
    this.backdropOnly = false,
  });

  static const _asset = 'img/listening_room_original.png';

  Widget _scene(BoxFit fit) => Image.asset(
    _asset,
    fit: fit,
    width: double.infinity,
    height: double.infinity,
  );

  Widget _blurredBackdrop() => ClipRect(
    child: ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: Transform.scale(scale: 1.16, child: _scene(BoxFit.cover)),
    ),
  );

  Widget _preservedScene() => Stack(
    fit: StackFit.expand,
    children: [
      _blurredBackdrop(),
      ColoredBox(color: Colors.black.withValues(alpha: 0.2)),
      _scene(BoxFit.contain),
    ],
  );

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      IgnorePointer(
        child: backdropOnly
            ? _blurredBackdrop()
            : preserveWholeScene
            ? _preservedScene()
            : _scene(BoxFit.cover),
      ),
      IgnorePointer(
        child: ColoredBox(color: Colors.black.withValues(alpha: 0.14)),
      ),
      child,
    ],
  );
}
