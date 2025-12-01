import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

class Mutex {
  // 指向最后一个进入等待队列的任务的 Future
  Future<void> _next = Future.value();

  /// 核心方法：确保 func 在同一时间只有一个在运行
  Future<T> protect<T>(FutureOr<T> Function() func) async {
    // 1. 获取当前锁的状态（即上一个任务的 Future）
    final previous = _next;

    // 2. 创建表示“当前任务完成”的 Completer
    final completer = Completer<void>();

    // 3. 更新 _next，让后续进来的任务等待“当前任务”完成
    // 注意：这一步是同步执行的，保证了排队的顺序
    _next = completer.future;

    try {
      // 4. 等待上一个任务完成（拿到锁）
      await previous;

      // 5. 进入临界区，执行实际逻辑
      return await func();
    } finally {
      // 6. 无论业务逻辑是否抛出异常，都要释放锁，通知下一个任务
      completer.complete();
    }
  }
}

abstract base class RandomAccessReader extends Reader {
  final Mutex _mutex = Mutex();

  Future<int> readIntoOffset(
    int offset,
    List<int> buffer, [
    int start = 0,
    int? end,
  ]);

  /// Gets the current byte position in the file.
  ///
  /// Returns a `Future<int>` that completes with the position.
  Future<int> position();

  /// Sets the byte position in the file.
  ///
  /// Returns a `Future<RandomAccessReader>` that completes with this
  /// random access file when the position has been set.
  Future<RandomAccessReader> setPosition(int position);

  Future<T> protectPosition<T>(
    FutureOr<T> Function(RandomAccessReader) func, {
    int? position,
  }) {
    return _mutex.protect(() async {
      if (position != null) {
        await setPosition(position);
      }
      return func(this);
    });
  }
}

abstract base class Reader {
  /// Closes the file.
  ///
  /// Returns a [Future] that completes when it has been closed.
  Future<void> close();

  /// Reads a byte from the file.
  ///
  /// Returns a `Future<int>` that completes with the byte,
  /// or with -1 if end-of-file has been reached.
  Future<int> readByte();

  /// Reads up to [count] bytes from a file.
  ///
  /// May return fewer than [count] bytes. This can happen, for example, when
  /// reading past the end of a file or when reading from a pipe that does not
  /// currently contain additional data.
  ///
  /// An empty [Uint8List] will only be returned when reading past the end of
  /// the file or when [count] is `0`.
  Future<Uint8List> read(int count);

  /// Reads bytes into an existing [buffer].
  ///
  /// Reads bytes and writes them into the range of [buffer]
  /// from [start] to [end].
  /// The [start] must be non-negative and no greater than [buffer].length.
  /// If [end] is omitted, it defaults to [buffer].length.
  /// Otherwise [end] must be no less than [start]
  /// and no greater than [buffer].length.
  ///
  /// Returns the number of bytes read. This maybe be less than `end - start`
  /// if the file doesn't have that many bytes to read.
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]);

  /// Gets the length of the file.
  ///
  /// Returns a `Future<int>` that completes with the length in bytes.
  Future<int?> length();
}

const _channel = MethodChannel('uri_random_access_reader');

final class UriRandomAccessReader extends RandomAccessReader {
  final int _id; // native 返回的句柄
  final String _uri;
  final int _length;
  int _position = 0; // 当前读指针（由 Dart 维护）

  UriRandomAccessReader._(this._id, this._uri, this._length);

  String get uri => _uri;

  @override
  Future<void> close() async {
    await _channel.invokeMethod('close', {'id': _id});
  }

  @override
  Future<int> readByte() async {
    final bytes = await read(1);
    if (bytes.isEmpty) return -1;
    return bytes[0];
  }

  @override
  Future<Uint8List> read(int count) async {
    if (count <= 0) return Uint8List(0);

    final remaining = _length - _position;
    if (remaining <= 0) return Uint8List(0);

    final toRead = math.min(count, remaining);
    final Uint8List? chunk = await _channel.invokeMethod<Uint8List>('read', {
      'id': _id,
      'offset': _position,
      'length': toRead,
    });

    final data = chunk ?? Uint8List(0);
    _position += data.length;
    return data;
  }

  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) async {
    end ??= buffer.length;
    if (start < 0 || end < start || end > buffer.length) {
      throw RangeError('Invalid range: $start - $end');
    }

    final count = end - start;
    final data = await read(count);
    buffer.setRange(start, start + data.length, data);
    return data.length;
  }

  /// 随机读取：从 [offset] 开始读入 [buffer] 的 [start..end)
  /// 注意：这里**不改变**当前 position，相当于“窥视一下”。
  @override
  Future<int> readIntoOffset(
    int offset,
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    end ??= buffer.length;
    if (start < 0 || end < start || end > buffer.length) {
      throw RangeError('Invalid range: $start - $end');
    }

    if (offset < 0) {
      throw RangeError('offset must be >= 0');
    }

    if (offset >= _length) {
      return 0; // EOF
    }

    final maxCount = math.min(end - start, _length - offset);
    if (maxCount <= 0) return 0;

    final Uint8List? chunk = await _channel.invokeMethod<Uint8List>('read', {
      'id': _id,
      'offset': offset,
      'length': maxCount,
    });

    final data = chunk ?? Uint8List(0);
    buffer.setRange(start, start + data.length, data);
    return data.length;
  }

  @override
  Future<int> position() async => _position;

  @override
  Future<RandomAccessReader> setPosition(int position) async {
    if (position < 0 || position > _length) {
      throw RangeError('Invalid position: $position');
    }
    _position = position;
    return this;
  }

  @override
  Future<int> length() async => _length;
}

Future<RandomAccessReader> uriToRandomAccess(Uri uri) async {
  final result = await _channel.invokeMapMethod<String, dynamic>('open', {
    'uri': uri.toString(),
  });

  if (result == null) {
    throw StateError('Failed to open uri: $uri');
  }

  final id = result['id'] as int;
  final length = (result['length'] as num).toInt();

  return UriRandomAccessReader._(id, uri.toString(), length);
}

class UriFileInfo {
  final String? fileName;
  final int size;
  final String? path;
  final String? mimeType;
  final DateTime? lastModified;

  UriFileInfo({
    this.fileName,
    required this.size,
    this.path,
    this.mimeType,
    this.lastModified,
  });

  @override
  String toString() {
    return 'UriFileInfo{fileName: $fileName, size: $size, path: $path, mimeType: $mimeType, lastModified: $lastModified}';
  }
}

class UriInfo {
  static const _channel = MethodChannel('com.doraemon.wind_send/uri');

  static Future<UriFileInfo?> getFileInfo(String uri) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getFileInfo',
        {'uri': uri},
      );

      if (result == null) {
        return null;
      }

      return UriFileInfo(
        fileName: result['fileName'] as String?,
        size: (result['size'] as num?)?.toInt() ?? 0,
        path: result['path'] as String?,
        mimeType: result['mimeType'] as String?,
        lastModified: result['lastModified'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (result['lastModified'] as num).toInt(),
              )
            : null,
      );
    } on PlatformException {
      return null;
    }
  }

  static Future<String?> getFilePath(String uri) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getFilePath',
        {'uri': uri},
      );
      return result?['path'] as String?;
    } on PlatformException {
      return null;
    }
  }
}
