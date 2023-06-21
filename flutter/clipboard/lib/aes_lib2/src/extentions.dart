part of aes_crypt;

extension _Uint8ListExtension on Uint8List {
  bool get isNullOrEmpty => this == null || this.isEmpty;

  Uint8List addList(Uint8List other) {
    int totalLength = this.length + other.length;
    Uint8List newList = Uint8List(totalLength);
    newList.setAll(0, this);
    newList.setRange(this.length, totalLength, other);
    return newList;
  }

  bool isNotEqual(Uint8List other) {
    if (identical(this, other)) return false;
    if (this != null && other == null) return true;
    int length = this.length;
    if (length != other.length) return true;
    for (int i = 0; i < length; i++) {
      if (this[i] != other[i]) return true;
    }
    return false;
  }

  // Converts bytes to UTF-16 string
  String toUtf16String([Endian endian = Endian.big]) {
    StringBuffer buffer = StringBuffer();
    int i = 0;
    if (this[0] == 0xFE && this[1] == 0xFF) {
      endian = Endian.big;
      i += 2;
    } else if (this[0] == 0xFF && this[1] == 0xFE) {
      endian = Endian.little;
      i += 2;
    }
    while (i < this.length) {
      int firstWord = (endian == Endian.big)?
        (this[i] << 8) + this[i + 1] : (this[i + 1] << 8) + this[i];
      if (0xD800 <= firstWord && firstWord <= 0xDBFF) {
        int secondWord = (endian == Endian.big)?
          (this[i + 2] << 8) + this[i + 3] : (this[i + 3] << 8) + this[i + 2];
        buffer.writeCharCode(((firstWord - 0xD800) << 10) + (secondWord - 0xDC00) + 0x10000);
        i += 4;
      } else {
        buffer.writeCharCode(firstWord);
        i += 2;
      }
    }
    return buffer.toString();
  }

  // Converts bytes to UTF-8 string
  String toUtf8String() {
    Uint8List data = this;
    if (this[0] == 0xEF && this[1] == 0xBB && this[2] == 0xBF) {
      data = this.buffer.asUint8List(3, this.length - 3); // skip BOM
    }
    return utf8.decode(data);
  }

  String toHexString() {
    StringBuffer str = StringBuffer();
    this.forEach((item) {
      str.write(item.toRadixString(16).toUpperCase().padLeft(2, '0'));
    });
    return str.toString();
  }

  void fillByZero() => this.fillRange(0, this.length, 0);
}

extension _StringExtension on String {
  // Returns true if string is: null or empty
  bool get isNullOrEmpty => this == null || this.isEmpty;

  // Converts UTF-16 string to bytes
  Uint8List toUtf16Bytes([Endian endian = Endian.big, bool bom = false]) {
    List<int> list =
        bom ? (endian == Endian.big ? [0xFE, 0xFF] : [0xFF, 0xFE]) : [];
    this.runes.forEach((rune) {
      if (rune >= 0x10000) {
        int firstWord = (rune >> 10) + 0xD800 - (0x10000 >> 10);
        int secondWord = (rune & 0x3FF) + 0xDC00;
        if (endian == Endian.big) {
          list.add(firstWord >> 8);
          list.add(firstWord & 0xFF);
          list.add(secondWord >> 8);
          list.add(secondWord & 0xFF);
        } else {
          list.add(firstWord & 0xFF);
          list.add(firstWord >> 8);
          list.add(secondWord & 0xFF);
          list.add(secondWord >> 8);
        }
      } else {
        if (endian == Endian.big) {
          list.add(rune >> 8);
          list.add(rune & 0xFF);
        } else {
          list.add(rune & 0xFF);
          list.add(rune >> 8);
        }
      }
    });
    return Uint8List.fromList(list);
  }

  // Converts string to UTF-8 bytes
  List<int> toUtf8Bytes([bool bom = false]) {
    if (bom) {
      Uint8List data = utf8.encode(this) as Uint8List;
      Uint8List dataWithBom = Uint8List(data.length + 3)
        ..setAll(0, [0xEF, 0xBB, 0xBF])
        ..setRange(3, data.length + 3, data);
      return dataWithBom;
    }
    return utf8.encode(this);
  }
}

extension _FileExtension on File {
  bool isReadable() {
    RandomAccessFile f;

    try {
      f = this.openSync(mode: FileMode.read);
    } on FileSystemException {
      return false;
    }

    try {
      f.lockSync(FileLock.shared);
    } on FileSystemException {
      f.closeSync();
      return false;
    }

    f.unlockSync();
    f.closeSync();
    return true;
  }
}
