import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../../language.dart';
import '../../utils/utils.dart';
import '../../toast.dart';
import 'history.dart';

/// Full-screen image preview dialog with pinch-to-zoom support
///
/// Features:
/// - Smooth open/close animations with fade and scale transitions
/// - Pinch-to-zoom with min 0.5x to max 5.0x scale
/// - Double-tap to toggle between fit and 2x zoom
/// - Share and save to gallery actions
/// - Elegant gradient overlays for controls
class ImagePreviewDialog extends StatefulWidget {
  final TransferHistoryItem item;
  final String? heroTag;

  const ImagePreviewDialog({super.key, required this.item, this.heroTag});

  @override
  State<ImagePreviewDialog> createState() => _ImagePreviewDialogState();

  /// Show the image preview dialog with smooth animation
  static Future<void> show(
    BuildContext context,
    TransferHistoryItem item, {
    String? heroTag,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) {
          return ImagePreviewDialog(item: item, heroTag: heroTag);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Fade in the background
          final backgroundAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          );

          // Scale and fade the content
          final scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          );

          return FadeTransition(
            opacity: backgroundAnimation,
            child: ScaleTransition(scale: scaleAnimation, child: child),
          );
        },
      ),
    );
  }
}

class _ImagePreviewDialogState extends State<ImagePreviewDialog>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  late AnimationController _animationController;

  bool _isLoading = true;
  String? _errorMessage;
  File? _imageFile;
  bool _isZoomed = false;
  bool _controlsVisible = true;

  // Track tap position for double-tap zoom
  Offset _doubleTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _loadImage();

    // Set immersive mode for better viewing experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      // Try to get image path from files payload first
      String? imagePath;

      final filesPayload = widget.item.filesPayload;
      if (filesPayload.files.isNotEmpty) {
        final firstFile = filesPayload.files.first;
        if (firstFile.path.isNotEmpty) {
          // Check if it's a relative path (needs resolution) or absolute
          if (p.isAbsolute(firstFile.path)) {
            imagePath = firstFile.path;
          } else {
            // Resolve relative path from payload directory
            imagePath = await toAbsolutePayloadPath(firstFile.path);
          }
        }
      }

      // Fallback to payloadPath if available
      if ((imagePath == null || imagePath.isEmpty) &&
          widget.item.payloadPath != null &&
          widget.item.payloadPath!.isNotEmpty) {
        if (p.isAbsolute(widget.item.payloadPath!)) {
          imagePath = widget.item.payloadPath;
        } else {
          imagePath = await toAbsolutePayloadPath(widget.item.payloadPath!);
        }
      }

      if (imagePath == null || imagePath.isEmpty) {
        setState(() {
          _errorMessage = AppLocale.imagePathNotExist;
          _isLoading = false;
        });
        return;
      }

      final file = File(imagePath);
      if (!await file.exists()) {
        setState(() {
          _errorMessage = AppLocale.imageFileNotExist;
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _imageFile = file;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '${AppLocale.loadImageFailed}|$e';
        _isLoading = false;
      });
    }
  }

  void _handleShare() async {
    // Capture context-dependent values BEFORE any async gap
    final fallbackText = context.formatString(AppLocale.image, []);
    final cannotShareMsg = context.formatString(
      AppLocale.cannotShareImageNotExist,
      [],
    );

    if (_imageFile == null || !await _imageFile!.exists()) {
      if (!mounted || !context.mounted) return;
      ToastResult(
        message: cannotShareMsg,
        status: ToastStatus.failure,
      ).showToast(context);
      return;
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(_imageFile!.path)],
          text:
              widget.item.filesPayload.files.firstOrNull?.name ?? fallbackText,
        ),
      );
    } catch (e) {
      if (!mounted || !context.mounted) return;
      ToastResult(
        message: context.formatString(AppLocale.shareFailedWithError, ['$e']),
        status: ToastStatus.failure,
      ).showToast(context);
    }
  }

  /// Check if we're on a mobile platform that supports gallery saving
  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Request storage/photos permission for saving to gallery
  Future<bool> _requestSavePermission() async {
    if (Platform.isAndroid) {
      // Android 13+ (API 33+) uses granular media permissions
      // For saving images, we need photos permission or storage permission
      final deviceInfo = await DeviceInfoPlugin().androidInfo;
      if (deviceInfo.version.sdkInt >= 33) {
        // Android 13+: Request photos permission
        final status = await Permission.photos.request();
        return status.isGranted;
      } else {
        // Android < 13: Request storage permission
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    } else if (Platform.isIOS) {
      // iOS: Request photos add permission
      final status = await Permission.photosAddOnly.request();
      return status.isGranted || status.isLimited;
    }
    return true; // Desktop platforms don't need permission
  }

  Future<void> _handleSave() async {
    if (_imageFile == null || !await _imageFile!.exists()) {
      if (!mounted || !context.mounted) return;
      ToastResult(
        message: context.formatString(AppLocale.cannotSaveImageNotExist, []),
        status: ToastStatus.failure,
      ).showToast(context);
      return;
    }

    try {
      final originalName =
          widget.item.filesPayload.files.firstOrNull?.name ??
          'WindSend_${DateTime.now().millisecondsSinceEpoch}.png';

      if (_isMobilePlatform) {
        // Mobile: Save to gallery using image_gallery_saver_plus
        await _saveToGallery(originalName);
      } else {
        // Desktop: Use file picker to let user choose save location
        await _saveWithFilePicker(originalName);
      }
    } catch (e) {
      if (!mounted || !context.mounted) return;
      ToastResult(
        message: context.formatString(AppLocale.saveFailedWithError, ['$e']),
        status: ToastStatus.failure,
      ).showToast(context);
    }
  }

  /// Save image to device gallery (Android/iOS)
  Future<void> _saveToGallery(String fileName) async {
    // Request permission first
    final hasPermission = await _requestSavePermission();
    if (!hasPermission) {
      if (!mounted || !context.mounted) return;
      ToastResult(
        message: context.formatString(AppLocale.storagePermissionRequired, []),
        status: ToastStatus.failure,
      ).showToast(context);
      return;
    }

    // Save to gallery
    final result = await ImageGallerySaverPlus.saveFile(
      _imageFile!.path,
      name: fileName,
      isReturnPathOfIOS: true,
    );

    if (!mounted || !context.mounted) return;

    // Check result - returns Map with 'isSuccess' key
    if (result is Map && result['isSuccess'] == true) {
      ToastResult(
        message: context.formatString(AppLocale.savedToGallery, []),
        status: ToastStatus.success,
      ).showToast(context);
    } else {
      final errorMsg = result is Map
          ? result['errorMessage']
          : result.toString();
      ToastResult(
        message: context.formatString(AppLocale.saveFailedWithError, [
          '$errorMsg',
        ]),
        status: ToastStatus.failure,
      ).showToast(context);
    }
  }

  /// Save image using file picker dialog (Desktop platforms)
  Future<void> _saveWithFilePicker(String fileName) async {
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: context.formatString(AppLocale.saveImageDialogTitle, []),
      fileName: fileName,
      type: FileType.image,
    );

    if (savePath == null) {
      // User cancelled
      return;
    }

    // Copy file to selected location
    await _imageFile!.copy(savePath);

    if (!mounted || !context.mounted) return;

    ToastResult(
      message: context.formatString(AppLocale.saved, []),
      status: ToastStatus.success,
    ).showToast(context);
  }

  void _handleClose() {
    Navigator.of(context).pop();
  }

  /// Toggle controls visibility on single tap
  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
  }

  /// Handle double-tap to toggle zoom
  void _handleDoubleTap() {
    if (_isZoomed) {
      // Animate back to identity
      _animateToMatrix(Matrix4.identity());
      _isZoomed = false;
    } else {
      // Zoom to 2x at the tap position
      final scale = 2.5;
      final position = _doubleTapPosition;

      // Calculate the focal point offset
      final x = -position.dx * (scale - 1);
      final y = -position.dy * (scale - 1);

      final matrix = Matrix4.identity()
        ..translateByDouble(x, y, 0.0, 1.0)
        ..scaleByDouble(scale, scale, 1.0, 1.0);

      _animateToMatrix(matrix);
      _isZoomed = true;
    }
  }

  /// Animate transformation matrix smoothly
  void _animateToMatrix(Matrix4 targetMatrix) {
    final beginMatrix = _transformationController.value.clone();

    _animationController.reset();

    final animation = Matrix4Tween(begin: beginMatrix, end: targetMatrix)
        .animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    void listener() {
      _transformationController.value = animation.value;
    }

    animation.addListener(listener);
    _animationController.forward().then((_) {
      animation.removeListener(listener);
    });
  }

  /// Track zoom state changes from InteractiveViewer
  void _onInteractionEnd(ScaleEndDetails details) {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    _isZoomed = scale > 1.1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Image viewer with gesture handling
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleControls,
                onDoubleTapDown: (details) {
                  _doubleTapPosition = details.localPosition;
                },
                onDoubleTap: _handleDoubleTap,
                child: _buildImageViewer(colorScheme),
              ),
            ),

            // Top bar with close and action buttons
            _buildTopBar(colorScheme),

            // Bottom info bar
            if (_imageFile != null && !_isLoading && _errorMessage == null)
              _buildBottomBar(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildImageViewer(ColorScheme colorScheme) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.formatString(AppLocale.loading, []),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      // Format the error message - handle both simple keys and keys with error details
      String displayError;
      if (_errorMessage!.contains('|')) {
        final parts = _errorMessage!.split('|');
        displayError = context.formatString(parts[0], [parts[1]]);
      } else {
        displayError = context.formatString(_errorMessage!, []);
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.broken_image_rounded,
                  size: 56,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                displayError,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: _handleClose,
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(context.formatString(AppLocale.back, [])),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    if (_imageFile == null) {
      return const SizedBox.shrink();
    }

    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 0.5,
      maxScale: 5.0,
      onInteractionEnd: _onInteractionEnd,
      child: Center(
        child: Image.file(
          _imageFile!,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (ctx, error, stackTrace) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  ctx.formatString(AppLocale.imageLoadFailed, []),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar(ColorScheme colorScheme) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      top: _controlsVisible ? 0 : -80,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _controlsVisible ? 1.0 : 0.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.75),
                Colors.black.withValues(alpha: 0.4),
                Colors.transparent,
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
          child: Row(
            children: [
              // Close button
              _buildControlButton(
                icon: Icons.close_rounded,
                tooltip: context.formatString(AppLocale.close, []),
                onPressed: _handleClose,
              ),

              const Spacer(),

              // Action buttons
              if (_imageFile != null) ...[
                // Save button
                _buildControlButton(
                  icon: Icons.save_alt_rounded,
                  tooltip: context.formatString(AppLocale.save, []),
                  onPressed: _handleSave,
                ),
                const SizedBox(width: 4),

                // Share button
                _buildControlButton(
                  icon: Icons.share_rounded,
                  tooltip: context.formatString(AppLocale.share, []),
                  onPressed: _handleShare,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Tooltip(
          message: tooltip,
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme colorScheme) {
    final fileName =
        widget.item.filesPayload.files.firstOrNull?.name ??
        context.formatString(AppLocale.image, []);
    final fileSize = formatBytes(widget.item.dataSize);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      bottom: _controlsVisible ? 0 : -100,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _controlsVisible ? 1.0 : 0.0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.8),
                Colors.black.withValues(alpha: 0.5),
                Colors.transparent,
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
          child: Row(
            children: [
              // File info
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fileSize,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              // Zoom hint (only show when not zoomed)
              if (!_isZoomed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.touch_app_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        context.formatString(AppLocale.doubleTapToZoom, []),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
