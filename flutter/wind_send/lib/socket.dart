import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';

class BroadcastSocket implements Socket {
  /// This is a broadcast stream of the socket.
  final Stream<Uint8List> stream;
  final Socket conn;

  BroadcastSocket(this.conn, this.stream);

  BroadcastSocket.fromSocket(Socket socket)
      : conn = socket,
        stream = socket.asBroadcastStream();

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
    return stream.isBroadcast;
  }

  @override
  Future<bool> get isEmpty {
    return stream.isEmpty;
  }

  @override
  Future<Uint8List> get first {
    return stream.first;
  }

  @override
  Future<Uint8List> get last {
    return stream.last;
  }

  @override
  Future<int> get length {
    return stream.length;
  }

  @override
  Future<Uint8List> get single {
    return stream.single;
  }

  @override
  Stream<Uint8List> asBroadcastStream({
    bool? cancelOnError,
    void Function(StreamSubscription<Uint8List>)? onListen,
    void Function(StreamSubscription<Uint8List>)? onCancel,
  }) {
    return stream;
  }

  @override
  Stream<S> transform<S>(StreamTransformer<Uint8List, S> streamTransformer) {
    return stream.transform(streamTransformer);
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
  Stream<Uint8List> timeout(Duration timeLimit,
      {void Function(EventSink<Uint8List>)? onTimeout}) {
    return stream.timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<List<Uint8List>> toList() {
    return stream.toList();
  }

  @override
  Future<Set<Uint8List>> toSet() {
    return stream.toSet();
  }

  @override
  Stream<Uint8List> skip(int count) {
    return stream.skip(count);
  }

  @override
  Stream<Uint8List> skipWhile(bool Function(Uint8List) test) {
    return stream.skipWhile(test);
  }

  @override
  Stream<Uint8List> take(int count) {
    return stream.take(count);
  }

  @override
  Stream<Uint8List> takeWhile(bool Function(Uint8List) test) {
    return stream.takeWhile(test);
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  Future<dynamic> pipe(StreamConsumer<Uint8List> streamConsumer) {
    return stream.pipe(streamConsumer);
  }

  @override
  Future<Uint8List> reduce(Uint8List Function(Uint8List, Uint8List) combine) {
    return stream.reduce(combine);
  }

  @override
  Future<Uint8List> singleWhere(bool Function(Uint8List) test,
      {Uint8List Function()? orElse}) {
    return stream.singleWhere(test, orElse: orElse);
  }

  @override
  Future<S> fold<S>(S initialValue, S Function(S, Uint8List) combine) {
    return stream.fold(initialValue, combine);
  }

  @override
  Future<void> forEach(void Function(Uint8List) action) {
    return stream.forEach(action);
  }

  @override
  Future<String> join([String separator = ""]) {
    return stream.join(separator);
  }

  @override
  Future<Uint8List> lastWhere(bool Function(Uint8List) test,
      {Uint8List Function()? orElse}) {
    return stream.lastWhere(test, orElse: orElse);
  }

  @override
  Stream<T> cast<T>() {
    return stream.cast<T>();
  }

  @override
  Stream<Uint8List> distinct([bool Function(Uint8List, Uint8List)? equals]) {
    return stream.distinct(equals);
  }

  @override
  Future<E> drain<E>([E? futureValue]) {
    return stream.drain<E>(futureValue);
  }

  @override
  Stream<T> expand<T>(Iterable<T> Function(Uint8List) f) {
    return stream.expand(f);
  }

  @override
  Future<Uint8List> firstWhere(bool Function(Uint8List) test,
      {Uint8List Function()? orElse}) {
    return stream.firstWhere(test, orElse: orElse);
  }

  @override
  Stream<Uint8List> handleError(Function onError,
      {bool Function(dynamic)? test}) {
    return stream.handleError(onError, test: test);
  }

  @override
  Stream<S> map<S>(S Function(Uint8List) convert) {
    return stream.map(convert);
  }

  @override
  Stream<Uint8List> where(bool Function(Uint8List) test) {
    return stream.where(test);
  }

  @override
  Stream<E> asyncMap<E>(FutureOr<E> Function(Uint8List) convert) {
    return stream.asyncMap(convert);
  }

  @override
  Stream<E> asyncExpand<E>(Stream<E>? Function(Uint8List) convert) {
    return stream.asyncExpand(convert);
  }

  @override
  Future<bool> any(bool Function(Uint8List) test) {
    return stream.any(test);
  }

  @override
  Future<bool> contains(Object? value) {
    return stream.contains(value);
  }

  @override
  Future<bool> every(bool Function(Uint8List) test) {
    return stream.every(test);
  }

  @override
  Future<Uint8List> elementAt(int index) {
    return stream.elementAt(index);
  }
}
