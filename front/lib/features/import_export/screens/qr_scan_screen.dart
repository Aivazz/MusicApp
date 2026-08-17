import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:ses/core/theme/app_theme.dart';

class QRScanScreen extends StatefulWidget {
  const QRScanScreen({super.key});

  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> with SingleTickerProviderStateMixin {
  final MobileScannerController controller = MobileScannerController();
  late AnimationController _animController;
  bool _isFlashOn = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;
    _isProcessing = true;
    
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final barcodeCapture = await controller.analyzeImage(image.path);
        if (barcodeCapture != null && barcodeCapture.barcodes.isNotEmpty) {
          final code = barcodeCapture.barcodes.first.rawValue;
          if (code != null && code.isNotEmpty) {
            if (mounted) Navigator.pop(context, code);
            return;
          }
        }
        if (mounted) {
          AppTheme.showSnackBar(context, "QR-код на изображении не найден");
        }
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showSnackBar(context, "Не удалось обработать изображение: $e");
      }
    } finally {
      _isProcessing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera scanner
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (_isProcessing) return;
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final code = barcodes.first.rawValue;
                if (code != null && code.isNotEmpty) {
                  _isProcessing = true;
                  Navigator.pop(context, code);
                }
              }
            },
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Iconsax.camera, color: Colors.white24, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        "Камера недоступна",
                        style: AppText.trackTitleActive.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Вы можете отсканировать QR-код из галереи",
                        style: AppText.caption,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Custom Scanning Overlay
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Сканирование QR-кода",
                      style: AppText.trackTitleActive.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Наведите камеру на QR-код Spotify или Яндекс",
                      style: AppText.caption.copyWith(color: Colors.white54),
                    ),
                    const SizedBox(height: 40),
                    
                    // Scanning square
                    Stack(
                      children: [
                        Container(
                          width: 260,
                          height: 260,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 2),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        
                        // Corner brackets
                        ..._buildCorners(),

                        // Laser line animation
                        AnimatedBuilder(
                          animation: _animController,
                          builder: (context, child) {
                            return Positioned(
                              top: 260 * _animController.value,
                              left: 12,
                              right: 12,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.accentGreen.withValues(alpha: 0.8),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.accentGreen.withValues(alpha: 0.1),
                                      AppColors.accentGreen,
                                      AppColors.accentGreen.withValues(alpha: 0.1),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 50),

                    // Gallery scan button
                    GestureDetector(
                      onTap: _pickFromGallery,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Iconsax.gallery, color: Colors.white, size: 20),
                            SizedBox(width: 12),
                            Text(
                              "Выбрать из галереи",
                              style: TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Control buttons (Back and Flash)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Back Button
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Iconsax.arrow_left_2, color: Colors.white, size: 18),
                    ),
                  ),
                ),
                
                // Flash Toggle
                GestureDetector(
                  onTap: () async {
                    await controller.toggleTorch();
                    setState(() {
                      _isFlashOn = !_isFlashOn;
                    });
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        _isFlashOn ? Iconsax.flash_1 : Iconsax.flash_slash,
                        color: _isFlashOn ? AppColors.accentGreen : Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCorners() {
    const double length = 24.0;
    const double thickness = 3.0;
    final color = AppColors.accentGreen;
    const radius = Radius.circular(24);

    return [
      // Top Left
      Positioned(
        top: 0,
        left: 0,
        child: Container(
          width: length,
          height: thickness,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(topLeft: radius),
          ),
        ),
      ),
      Positioned(
        top: 0,
        left: 0,
        child: Container(
          width: thickness,
          height: length,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(topLeft: radius),
          ),
        ),
      ),
      // Top Right
      Positioned(
        top: 0,
        right: 0,
        child: Container(
          width: length,
          height: thickness,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(topRight: radius),
          ),
        ),
      ),
      Positioned(
        top: 0,
        right: 0,
        child: Container(
          width: thickness,
          height: length,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(topRight: radius),
          ),
        ),
      ),
      // Bottom Left
      Positioned(
        bottom: 0,
        left: 0,
        child: Container(
          width: length,
          height: thickness,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(bottomLeft: radius),
          ),
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        child: Container(
          width: thickness,
          height: length,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(bottomLeft: radius),
          ),
        ),
      ),
      // Bottom Right
      Positioned(
        bottom: 0,
        right: 0,
        child: Container(
          width: length,
          height: thickness,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(bottomRight: radius),
          ),
        ),
      ),
      Positioned(
        bottom: 0,
        right: 0,
        child: Container(
          width: thickness,
          height: length,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(bottomRight: radius),
          ),
        ),
      ),
    ];
  }
}
