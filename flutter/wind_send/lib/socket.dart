import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';

class BroadcastSocket implements Socket {
  /// This is a broadcast stream of the socket.
  Stream<Uint8List> _stream;
  final Socket conn;

  Stream<Uint8List> get stream => _stream;

  updateStream(Stream<Uint8List> value) {
    _stream = value;
  }

  BroadcastSocket(this.conn, this._stream);

  BroadcastSocket.fromSocket(Socket socket)
    : conn = socket,
      _stream = socket.asBroadcastStream();

  @override
  void add(List<int> data) {
    conn.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    conn.addError(error, stackTrace);
  }

  @override
  Future<dynamic> addStream(Stream<List<int>> dataStream) {
    return conn.addStream(dataStream);
  }

  @override
  Future<dynamic> flush() {
    return conn.flush();
  }

  @override
  void destroy() {
    conn.destroy();
  }

  @override
  void write(Object? object) {
    conn.write(object);
  }

  @override
  void writeAll(Iterable objects, [String separator = ""]) {
    conn.writeAll(objects, separator);
  }

  @override
  void writeCharCode(int charCode) {
    conn.writeCharCode(charCode);
  }

  @override
  void writeln([Object? object = ""]) {
    conn.writeln(object);
  }

  @override
  Future<dynamic> close() {
    return conn.close();
  }

  @override
  Uint8List getRawOption(RawSocketOption option) {
    return conn.getRawOption(option);
  }

  @override
  bool setOption(SocketOption option, bool value) {
    return conn.setOption(option, value);
  }

  @override
  void setRawOption(RawSocketOption option) {
    conn.setRawOption(option);
  }

  @override
  Future<void> get done {
    return conn.done;
  }

  @override
  int get port {
    return conn.port;
  }

  @override
  InternetAddress get remoteAddress {
    return conn.remoteAddress;
  }

  @override
  int get remotePort {
    return conn.remotePort;
  }

  @override
  bool get isBroadcast {
    return _stream.isBroadcast;
  }

  @override
  Future<bool> get isEmpty {
    return _stream.isEmpty;
  }

  @override
  Future<Uint8List> get first {
    return _stream.first;
  }

  @override
  Future<Uint8List> get last {
    return _stream.last;
  }

  @override
  Future<int> get length {
    return _stream.length;
  }

  @override
  Future<Uint8List> get single {
    return _stream.single;
  }

  @override
  Stream<Uint8List> asBroadcastStream({
    bool? cancelOnError,
    void Function(StreamSubscription<Uint8List>)? onListen,
    void Function(StreamSubscription<Uint8List>)? onCancel,
  }) {
    return _stream;
  }

  @override
  Stream<S> transform<S>(StreamTransformer<Uint8List, S> streamTransformer) {
    return _stream.transform(streamTransformer);
  }

  @override
  Encoding get encoding {
    return conn.encoding;
  }

  @override
  set encoding(Encoding encoding) {
    conn.encoding = encoding;
  }

  @override
  InternetAddress get address {
    return conn.address;
  }

  @override
  Stream<Uint8List> timeout(
    Duration timeLimit, {
    void Function(EventSink<Uint8List>)? onTimeout,
  }) {
    return _stream.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<List<Uint8List>> toList() {
    return _stream.toList();
  }

  @override
  Future<Set<Uint8List>> toSet() {
    return _stream.toSet();
  }

  @override
  Stream<Uint8List> skip(int count) {
    return _stream.skip(count);
  }

  @override
  Stream<Uint8List> skipWhile(bool Function(Uint8List) test) {
    return _stream.skipWhile(test);
  }

  @override
  Stream<Uint8List> take(int count) {
    return _stream.take(count);
  }

  @override
  Stream<Uint8List> takeWhile(bool Function(Uint8List) test) {
    return _stream.takeWhile(test);
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<dynamic> pipe(StreamConsumer<Uint8List> streamConsumer) {
    return _stream.pipe(streamConsumer);
  }

  @override
  Future<Uint8List> reduce(Uint8List Function(Uint8List, Uint8List) combine) {
    return _stream.reduce(combine);
  }

  @override
  Future<Uint8List> singleWhere(
    bool Function(Uint8List) test, {
    Uint8List Function()? orElse,
  }) {
    return _stream.singleWhere(test, orElse: orElse);
  }

  @override
  Future<S> fold<S>(S initialValue, S Function(S, Uint8List) combine) {
    return _stream.fold(initialValue, combine);
  }

  @override
  Future<void> forEach(void Function(Uint8List) action) {
    return _stream.forEach(action);
  }

  @override
  Future<String> join([String separator = ""]) {
    return _stream.join(separator);
  }

  @override
  Future<Uint8List> lastWhere(
    bool Function(Uint8List) test, {
    Uint8List Function()? orElse,
  }) {
    return _stream.lastWhere(test, orElse: orElse);
  }

  @override
  Stream<T> cast<T>() {
    return _stream.cast<T>();
  }

  @override
  Stream<Uint8List> distinct([bool Function(Uint8List, Uint8List)? equals]) {
    return _stream.distinct(equals);
  }

  @override
  Future<E> drain<E>([E? futureValue]) {
    return _stream.drain<E>(futureValue);
  }

  @override
  Stream<T> expand<T>(Iterable<T> Function(Uint8List) f) {
    return _stream.expand(f);
  }

  @override
  Future<Uint8List> firstWhere(
    bool Function(Uint8List) test, {
    Uint8List Function()? orElse,
  }) {
    return _stream.firstWhere(test, orElse: orElse);
  }

  @override
  Stream<Uint8List> handleError(
    Function onError, {
    bool Function(dynamic)? test,
  }) {
    return _stream.handleError(onError, test: test);
  }

  @override
  Stream<S> map<S>(S Function(Uint8List) convert) {
    return _stream.map(convert);
  }

  @override
  Stream<Uint8List> where(bool Function(Uint8List) test) {
    return _stream.where(test);
  }

  @override
  Stream<E> asyncMap<E>(FutureOr<E> Function(Uint8List) convert) {
    return _stream.asyncMap(convert);
  }

  @override
  Stream<E> asyncExpand<E>(Stream<E>? Function(Uint8List) convert) {
    return _stream.asyncExpand(convert);
  }

  @override
  Future<bool> any(bool Function(Uint8List) test) {
    return _stream.any(test);
  }

  @override
  Future<bool> contains(Object? value) {
    return _stream.contains(value);
  }

  @override
  Future<bool> every(bool Function(Uint8List) test) {
    return _stream.every(test);
  }

  @override
  Future<Uint8List> elementAt(int index) {
    return _stream.elementAt(index);
  }
}
