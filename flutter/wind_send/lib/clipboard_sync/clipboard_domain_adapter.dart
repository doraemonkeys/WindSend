import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:super_clipboard/super_clipboard.dart';

import 'clipboard_domain.dart';

typedef ClipboardDomainLogFn = void Function(String message);
typedef ClipboardPlainTextFallbackReader = Future<String?> Function();

abstract interface class ClipboardDomainAdapter {
  Future<ClipboardCaptureResult> captureSnapshot({
    ClipboardObservationSource source = ClipboardObservationSource.manualRead,
  });

  Future<ClipboardApplyResult> applyPayload(
    ClipboardPayload payload, {
    ClipboardApplyOptions options = const ClipboardApplyOptions(),
  });
}

Future<ClipboardCaptureResult> captureSnapshotWithPlainTextFallback({
  required ClipboardDomainAdapter adapter,
  required ClipboardObservationSource source,
  required bool allowPlainTextFallback,
  required ClipboardPlainTextFallbackReader readPlainTextFallback,
  ClipboardDomainLogFn? logger,
}) async {
  final captured = await adapter.captureSnapshot(source: source);
  if (captured case ClipboardCaptureSuccess()) {
    return captured;
  }
  if (!allowPlainTextFallback) {
    return captured;
  }

  final plainText = await readPlainTextFallback();
  if (plainText == null) {
    return captured;
  }

  logger?.call(
    'Plain-text fallback produced clipboard content for ${source.name} after ${captured.runtimeType}.',
  );
  return ClipboardCaptureSuccess(
    ClipboardSnapshot.observed(
      payload: ClipboardPayload.text(TextBundle(plainText: plainText)),
      observedAt: DateTime.now().toUtc(),
      source: source,
    ),
  );
}

/// Bridges `super_clipboard` into Phase 0 domain objects so later sync-session
/// code can depend on one semantic boundary instead of reaching into platform
/// APIs at every call site.
@immutable
final class SuperClipboardDomainAdapter implements ClipboardDomainAdapter {
  const SuperClipboardDomainAdapter({this.logger});

  final ClipboardDomainLogFn? logger;

  @override
  Future<ClipboardCaptureResult> captureSnapshot({
    ClipboardObservationSource source = ClipboardObservationSource.manualRead,
  }) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return const ClipboardCaptureUnavailable(
        'Clipboard API is not supported on this platform.',
      );
    }

    final reader = await clipboard.read();

    final imagePayload = await _tryReadImagePayload(reader);
    if (imagePayload != null) {
      return ClipboardCaptureSuccess(
        ClipboardSnapshot.observed(
          payload: imagePayload,
          observedAt: DateTime.now().toUtc(),
          source: source,
        ),
      );
    }

    final textBundle = await _tryReadTextBundle(reader);
    if (textBundle != null) {
      return ClipboardCaptureSuccess(
        ClipboardSnapshot.observed(
          payload: ClipboardPayload.text(textBundle),
          observedAt: DateTime.now().toUtc(),
          source: source,
        ),
      );
    }

    return const ClipboardCaptureEmpty();
  }

  @override
  Future<ClipboardApplyResult> applyPayload(
    ClipboardPayload payload, {
    ClipboardApplyOptions options = const ClipboardApplyOptions(),
  }) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return ClipboardApplyResult.failed(
        payloadKind: payload.kind,
        message: 'Clipboard API is not supported on this platform.',
      );
    }

    final item = DataWriterItem();

    switch (payload) {
      case ClipboardTextPayload(:final textBundle):
        final canWriteHtml =
            options.includeHtmlRepresentation &&
            textBundle.html != null &&
            textBundle.html!.isNotEmpty;
        final requiresHtmlFallback = textBundle.html != null && !canWriteHtml;

        if (requiresHtmlFallback && !options.allowPlainTextFallback) {
          return ClipboardApplyResult.failed(
            payloadKind: payload.kind,
            message:
                'HTML representation is unavailable and plain-text fallback is disabled.',
          );
        }

        item.add(Formats.plainText(textBundle.plainText));
        if (canWriteHtml) {
          item.add(Formats.htmlText(textBundle.html!));
        }

        await clipboard.write(<DataWriterItem>[item]);

        if (requiresHtmlFallback) {
          return ClipboardApplyResult.appliedWithDegradation(
            payload: payload,
            degradations: const <ClipboardApplyDegradation>{
              ClipboardApplyDegradation.htmlDropped,
            },
          );
        }

        return ClipboardApplyResult.applied(payload: payload);
      case ClipboardImagePngPayload(:final pngBytes):
        item.add(Formats.png(pngBytes));
        await clipboard.write(<DataWriterItem>[item]);
        return ClipboardApplyResult.applied(payload: payload);
    }
  }

  Future<TextBundle?> _tryReadTextBundle(ClipboardReader reader) async {
    final plainText = await _readValueSafely<String>(
      reader: reader,
      format: Formats.plainText,
      debugName: 'plainText',
    );
    if (plainText == null) {
      return null;
    }

    final html = await _readValueSafely<String>(
      reader: reader,
      format: Formats.htmlText,
      debugName: 'htmlText',
    );

    return TextBundle(plainText: plainText, html: html);
  }

  Future<ClipboardImagePngPayload?> _tryReadImagePayload(
    ClipboardReader reader,
  ) async {
    const imageFormats = <SimpleFileFormat>[
      Formats.png,
      Formats.jpeg,
      Formats.bmp,
      Formats.gif,
      Formats.tiff,
      Formats.webp,
    ];

    for (final format in imageFormats) {
      if (!reader.canProvide(format)) {
        continue;
      }

      final imageBytes = await _readFileBytesSafely(reader, format);
      if (imageBytes == null) {
        continue;
      }

      if (identical(format, Formats.png)) {
        return ClipboardImagePngPayload(imageBytes);
      }

      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        logger?.call('Failed to decode clipboard image for PNG normalization.');
        continue;
      }

      return ClipboardImagePngPayload(
        Uint8List.fromList(img.encodePng(decoded)),
      );
    }

    return null;
  }

  Future<T?> _readValueSafely<T extends Object>({
    required ClipboardReader reader,
    required ValueFormat<T> format,
    required String debugName,
  }) async {
    try {
      if (!reader.canProvide(format)) {
        return null;
      }
      return await reader.readValue(format);
    } catch (error) {
      logger?.call('Clipboard value read failed for $debugName: $error');
      return null;
    }
  }

  Future<Uint8List?> _readFileBytesSafely(
    ClipboardReader reader,
    SimpleFileFormat format,
  ) async {
    final completer = Completer<Uint8List?>();

    try {
      reader.getFile(format, (file) async {
        try {
          final bytes = await file
              .getStream()
              .expand((chunk) => chunk)
              .toList();
          completer.complete(Uint8List.fromList(bytes));
        } catch (error) {
          logger?.call(
            'Clipboard file read failed for ${_debugNameForFileFormat(format)}: $error',
          );
          completer.complete(null);
        }
      });
    } catch (error) {
      logger?.call(
        'Clipboard file request failed for ${_debugNameForFileFormat(format)}: $error',
      );
      return null;
    }

    return completer.future;
  }
}

String _debugNameForFileFormat(SimpleFileFormat format) {
  if (identical(format, Formats.png)) return 'png';
  if (identical(format, Formats.jpeg)) return 'jpeg';
  if (identical(format, Formats.bmp)) return 'bmp';
  if (identical(format, Formats.gif)) return 'gif';
  if (identical(format, Formats.tiff)) return 'tiff';
  if (identical(format, Formats.webp)) return 'webp';
  return format.providerFormat;
}
