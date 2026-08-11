import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../theme/theme.dart';

final barcodeScannerProvider = Provider<BarcodeScanner>((ref) {
  return const CameraBarcodeScanner();
});

abstract interface class BarcodeScanner {
  Future<String?> scan(BuildContext context);
}

class CameraBarcodeScanner implements BarcodeScanner {
  const CameraBarcodeScanner();

  @override
  Future<String?> scan(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const BarcodeScannerScreen(),
      ),
    );
  }
}

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  static const previewKey = Key('nutrition.barcodeScanner.preview');

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const <BarcodeFormat>[
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.itf14,
      BarcodeFormat.code128,
    ],
  );
  bool _completed = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan barcode'),
      ),
      body: MobileScanner(
        key: BarcodeScannerScreen.previewKey,
        controller: _controller,
        fit: BoxFit.cover,
        onDetect: _onDetect,
        errorBuilder: (context, _) => ColoredBox(
          color: context.colors.background,
          child: Center(
            child: Text(
              'Camera unavailable',
              style: context.textStyles.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
        overlayBuilder: (context, constraints) {
          final size = constraints.biggest;
          final width = (size.width * 0.78).clamp(240.0, 360.0);
          final height = width * 0.56;
          return Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
                borderRadius: AppRadii.cardMd,
              ),
              child: SizedBox(width: width, height: height),
            ),
          );
        },
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_completed) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) {
        continue;
      }
      _completed = true;
      Navigator.of(context).pop(value);
      return;
    }
  }
}
