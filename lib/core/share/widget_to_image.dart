import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Renders [child] to a PNG entirely off-screen and returns the encoded bytes.
///
/// The widget is laid out and painted in a throwaway render tree that is never
/// attached to the live [WidgetsBinding] — so nothing flashes on screen and the
/// capture doesn't depend on the widget being mounted/visible. Fonts already
/// loaded by the running app (the bundled `BarlowCondensed` / `Manrope`
/// families, the Material icon font) are available to the render, so the
/// result looks identical to what the
/// same widget would draw on screen.
///
/// [logicalSize] is the child's size in logical pixels; the PNG is
/// [logicalSize] × [pixelRatio] device pixels (e.g. 360×640 @ 3 ⇒ 1080×1920),
/// which is why the same render doubles as high-res store-screenshot art.
///
/// [view] anchors the render tree to a real [ui.FlutterView]; pass
/// `View.of(context)` from a mounted widget (or `tester.view` in tests).
///
/// Returns null only if the platform fails to encode the image; the caller is
/// expected to fall back to a non-image path rather than surface an error.
Future<Uint8List?> renderWidgetToPng({
  required Widget child,
  required Size logicalSize,
  required ui.FlutterView view,
  double pixelRatio = 3,
}) async {
  // The boundary is the node we snapshot; centring it inside a same-sized
  // RenderView means the captured bounds line up exactly with [logicalSize].
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(logicalSize),
      physicalConstraints: BoxConstraints.tight(logicalSize * pixelRatio),
      devicePixelRatio: pixelRatio,
    ),
    child: RenderPositionedBox(alignment: Alignment.center, child: boundary),
  );

  final pipelineOwner = PipelineOwner();
  final buildOwner = BuildOwner(focusManager: FocusManager());

  pipelineOwner.rootNode = renderView;
  renderView.prepareInitialFrame();

  // The card draws its own opaque background and reads no app theme, but it does
  // need a Directionality, and a MediaQuery keeps any descendant that probes it
  // (text scaling, reduced motion) from throwing.
  //
  // Text scaling is pinned OFF. [logicalSize] is fixed brand art, not a
  // responsive layout: inheriting the device's accessibility text scale from
  // the view grew the type inside a canvas that cannot grow with it, so a user
  // at 1.6× exported a poster with its rank and profile lines clipped — and an
  // off-screen render has no overflow banner to warn anyone. The share is a
  // picture for other people's screens; the reader's own font setting is not
  // part of it.
  RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData.fromView(
          view,
        ).copyWith(textScaler: TextScaler.noScaling),
        child: child,
      ),
    ),
  ).attachToRenderTree(buildOwner);

  buildOwner.finalizeTree();
  pipelineOwner
    ..flushLayout()
    ..flushCompositingBits()
    ..flushPaint();

  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
