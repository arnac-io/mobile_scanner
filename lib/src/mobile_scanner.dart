import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

enum Ratio { ratio_4_3, ratio_16_9 }

/// A widget showing a live camera preview.
class MobileScanner extends StatefulWidget {
  /// The controller of the camera.
  final MobileScannerController? controller;

  /// Function that gets called when a Barcode is detected.
  ///
  /// [barcode] The barcode object with all information about the scanned code.
  /// [args] Information about the state of the MobileScanner widget
  final Function(Barcode barcode, MobileScannerArguments? args) onDetect;

  /// TODO: Function that gets called when the Widget is initialized. Can be usefull
  /// to check wether the device has a torch(flash) or not.
  ///
  /// [args] Information about the state of the MobileScanner widget
  // final Function(MobileScannerArguments args)? onInitialize;

  /// Handles how the widget should fit the screen.
  final BoxFit fit;

  /// Set to false if you don't want duplicate scans.
  final bool allowDuplicates;

  /// if set barcodes will only be scanned if they fall within this [Rect]
  /// useful for having a cut-out overlay for example. these [Rect]
  /// coordinates are relative to the widget size, so by how much your
  /// rectangle overlays the actual image can depend on things like the
  /// [BoxFit]
  final Rect? scanWindow;

  /// Create a [MobileScanner] with a [controller], the [controller] must has been initialized.
  const MobileScanner({
    Key? key,
    required this.onDetect,
    this.controller,
    this.fit = BoxFit.cover,
    this.allowDuplicates = false,
    this.scanWindow,
  }) : super(key: key);

  @override
  State<MobileScanner> createState() => _MobileScannerState();
}

class _MobileScannerState extends State<MobileScanner>
    with WidgetsBindingObserver {
  late MobileScannerController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = widget.controller ?? MobileScannerController();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!controller.isStarting) controller.start();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        controller.stop();
        break;
    }
  }

  String? lastScanned;

  /// the [scanWindow] rect will be relative and scaled to the [widgetSize] not the texture. so it is possible,
  /// depending on the [fit], for the [scanWindow] to partially or not at all overlap the [textureSize]
  ///
  /// since when using a [BoxFit] the content will always be centered on its parent. we can convert the rect
  /// to be relative to the texture.
  ///
  /// since the textures size and the actuall image (on the texture size) might not be the same, we also need to
  /// calculate the scanWindow in terms of percentages of the texture, not pixels.
  Rect calculateScanWindowRelativeToTextureInPercentage(
    BoxFit fit,
    Rect scanWindow,
    Size textureSize,
    Size widgetSize,
  ) {
    /// map the texture size to get its new size after fitted to screen
    final fittedSizes = applyBoxFit(fit, textureSize, widgetSize);
    final fittedTextureSize = fittedSizes.destination;

    final minX = widgetSize.width / 2 - fittedTextureSize.width / 2;
    final minY = widgetSize.height / 2 - fittedTextureSize.height / 2;
    final width = fittedTextureSize.width;
    final height = fittedTextureSize.height;

    final textureWindow = Rect.fromLTWH(minX, minY, width, height);

    /// create a new scan window and with only the area of the rect intersecting the texture
    final scanWindowInTexture = scanWindow.intersect(textureWindow);

    /// update the scanWindow left and top to be relative to the texture not the widget
    final newLeft = scanWindowInTexture.left - minX;
    final newTop = scanWindowInTexture.top - minY;
    final newWidth = scanWindowInTexture.width;
    final newHeight = scanWindowInTexture.height;

    /// new scanWindow that is adapted to the boxfit and relative to the texture
    final windowInTexture = Rect.fromLTWH(newLeft, newTop, newWidth, newHeight);

    /// get the scanWindow as a percentage of the texture
    final percentageLeft = windowInTexture.left / fittedTextureSize.width;
    final percentageRight = windowInTexture.right / fittedTextureSize.width;
    final percentageTop = windowInTexture.top / fittedTextureSize.height;
    final percentagebottom = windowInTexture.bottom / fittedTextureSize.height;

    /// this rectangle can be send to native code and used to cut out a rectangle of the scan image
    return Rect.fromLTRB(
      percentageLeft,
      percentageRight,
      percentageTop,
      percentagebottom,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, BoxConstraints constraints) {
        return ValueListenableBuilder(
          valueListenable: controller.args,
          builder: (context, value, child) {
            value = value as MobileScannerArguments?;
            if (value == null) {
              return Container(color: Colors.black);
            } else {
              if (widget.scanWindow != null) {
                final window = calculateScanWindowRelativeToTextureInPercentage(
                  widget.fit,
                  widget.scanWindow!,
                  value.size,
                  Size(constraints.maxWidth, constraints.maxHeight),
                );
                print(window);
                controller.updateScanWindow(window);
              }

              controller.barcodes.listen((barcode) {
                if (!widget.allowDuplicates) {
                  if (lastScanned != barcode.rawValue) {
                    lastScanned = barcode.rawValue;
                    widget.onDetect(barcode, value! as MobileScannerArguments);
                  }
                } else {
                  widget.onDetect(barcode, value! as MobileScannerArguments);
                }
              });
              return ClipRect(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height,
                  child: FittedBox(
                    fit: widget.fit,
                    child: SizedBox(
                      width: value.size.width,
                      height: value.size.height,
                      child: kIsWeb
                          ? HtmlElementView(viewType: value.webId!)
                          : Texture(textureId: value.textureId!),
                    ),
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }

  @override
  void didUpdateWidget(covariant MobileScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == null) {
      if (widget.controller != null) {
        controller.dispose();
        controller = widget.controller!;
      }
    } else {
      if (widget.controller == null) {
        controller = MobileScannerController();
      } else if (oldWidget.controller != widget.controller) {
        controller = widget.controller!;
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
