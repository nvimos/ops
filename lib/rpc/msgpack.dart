import 'dart:convert';
import 'dart:typed_data';

/// An ext value that has no special meaning here.
class MsgExt {
  MsgExt(this.type, this.data);
  final int type;
  final Uint8List data;

  @override
  bool operator ==(Object other) =>
      other is MsgExt && other.type == type && _bytesEq(other.data, data);

  @override
  int get hashCode => Object.hash(type, data.length);
}

bool _bytesEq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Encode a Dart value (null, bool, int, double, String, List, Map, Uint8List, MsgExt).
Uint8List msgEncode(Object? value) {
  final b = BytesBuilder(copy: false);
  _enc(b, value);
  return b.takeBytes();
}

void _u8(BytesBuilder b, int v) => b.addByte(v & 0xff);

void _be(BytesBuilder b, int v, int bytes) {
  final d = ByteData(8)..setUint64(0, v);
  b.add(d.buffer.asUint8List(8 - bytes, bytes));
}

void _enc(BytesBuilder b, Object? v) {
  if (v == null) {
    _u8(b, 0xc0);
  } else if (v is bool) {
    _u8(b, v ? 0xc3 : 0xc2);
  } else if (v is int) {
    if (v >= 0) {
      if (v < 0x80) {
        _u8(b, v);
      } else if (v < 0x100) {
        _u8(b, 0xcc);
        _u8(b, v);
      } else if (v < 0x10000) {
        _u8(b, 0xcd);
        _be(b, v, 2);
      } else if (v < 0x100000000) {
        _u8(b, 0xce);
        _be(b, v, 4);
      } else {
        _u8(b, 0xcf);
        _be(b, v, 8);
      }
    } else {
      if (v >= -32) {
        _u8(b, v);
      } else if (v >= -128) {
        _u8(b, 0xd0);
        _u8(b, v);
      } else if (v >= -32768) {
        _u8(b, 0xd1);
        _be(b, v, 2);
      } else if (v >= -2147483648) {
        _u8(b, 0xd2);
        _be(b, v, 4);
      } else {
        _u8(b, 0xd3);
        _be(b, v, 8);
      }
    }
  } else if (v is double) {
    _u8(b, 0xcb);
    final d = ByteData(8)..setFloat64(0, v);
    b.add(d.buffer.asUint8List());
  } else if (v is String) {
    final s = utf8.encode(v);
    final n = s.length;
    if (n < 32) {
      _u8(b, 0xa0 | n);
    } else if (n < 0x100) {
      _u8(b, 0xd9);
      _u8(b, n);
    } else if (n < 0x10000) {
      _u8(b, 0xda);
      _be(b, n, 2);
    } else {
      _u8(b, 0xdb);
      _be(b, n, 4);
    }
    b.add(s);
  } else if (v is Uint8List) {
    final n = v.length;
    if (n < 0x100) {
      _u8(b, 0xc4);
      _u8(b, n);
    } else if (n < 0x10000) {
      _u8(b, 0xc5);
      _be(b, n, 2);
    } else {
      _u8(b, 0xc6);
      _be(b, n, 4);
    }
    b.add(v);
  } else if (v is List) {
    final n = v.length;
    if (n < 16) {
      _u8(b, 0x90 | n);
    } else if (n < 0x10000) {
      _u8(b, 0xdc);
      _be(b, n, 2);
    } else {
      _u8(b, 0xdd);
      _be(b, n, 4);
    }
    for (final e in v) {
      _enc(b, e);
    }
  } else if (v is Map) {
    final n = v.length;
    if (n < 16) {
      _u8(b, 0x80 | n);
    } else if (n < 0x10000) {
      _u8(b, 0xde);
      _be(b, n, 2);
    } else {
      _u8(b, 0xdf);
      _be(b, n, 4);
    }
    v.forEach((k, e) {
      _enc(b, k);
      _enc(b, e);
    });
  } else if (v is MsgExt) {
    final n = v.data.length;
    const fixed = {1: 0xd4, 2: 0xd5, 4: 0xd6, 8: 0xd7, 16: 0xd8};
    if (fixed.containsKey(n)) {
      _u8(b, fixed[n]!);
    } else if (n < 0x100) {
      _u8(b, 0xc7);
      _u8(b, n);
    } else if (n < 0x10000) {
      _u8(b, 0xc8);
      _be(b, n, 2);
    } else {
      _u8(b, 0xc9);
      _be(b, n, 4);
    }
    _u8(b, v.type);
    b.add(v.data);
  } else {
    throw ArgumentError('cannot msgpack-encode ${v.runtimeType}');
  }
}

class _Incomplete implements Exception {
  const _Incomplete();
}

/// Decodes a byte stream into msgpack values, across chunk boundaries.
///
/// Ext types 0, 1, 2 (Neovim's Buffer, Window, Tabpage handles) decode to their integer id.
class MsgDecoder {
  Uint8List _buf = Uint8List(0);
  int _pos = 0;

  /// Feed bytes; returns every complete value they finish.
  List<Object?> add(List<int> chunk) {
    if (_pos > 0) {
      _buf = Uint8List.sublistView(_buf, _pos);
      _pos = 0;
    }
    final merged = Uint8List(_buf.length + chunk.length)
      ..setAll(0, _buf)
      ..setAll(_buf.length, chunk);
    _buf = merged;
    final out = <Object?>[];
    while (_pos < _buf.length) {
      final start = _pos;
      try {
        out.add(_read());
      } on _Incomplete {
        _pos = start;
        break;
      }
    }
    return out;
  }

  int _byte() {
    if (_pos >= _buf.length) throw const _Incomplete();
    return _buf[_pos++];
  }

  Uint8List _take(int n) {
    if (_pos + n > _buf.length) throw const _Incomplete();
    final v = Uint8List.sublistView(_buf, _pos, _pos + n);
    _pos += n;
    return v;
  }

  ByteData _bd(int n) => ByteData.sublistView(_take(n));

  int _uint(int n) {
    final d = _bd(n);
    switch (n) {
      case 1:
        return d.getUint8(0);
      case 2:
        return d.getUint16(0);
      case 4:
        return d.getUint32(0);
      default:
        return d.getUint64(0);
    }
  }

  String _str(int n) => utf8.decode(_take(n), allowMalformed: true);

  List<Object?> _list(int n) => List<Object?>.generate(n, (_) => _read(), growable: true);

  Map<Object?, Object?> _map(int n) {
    final m = <Object?, Object?>{};
    for (var i = 0; i < n; i++) {
      final k = _read();
      m[k] = _read();
    }
    return m;
  }

  Object? _ext(int n) {
    final type = _byte();
    final data = Uint8List.fromList(_take(n));
    if (type >= 0 && type <= 2) {
      final inner = MsgDecoder().add(data);
      if (inner.isNotEmpty && inner.first is int) return inner.first;
    }
    return MsgExt(type, data);
  }

  Object? _read() {
    final t = _byte();
    if (t <= 0x7f) return t;
    if (t >= 0xe0) return t - 0x100;
    if (t & 0xe0 == 0xa0) return _str(t & 0x1f);
    if (t & 0xf0 == 0x90) return _list(t & 0x0f);
    if (t & 0xf0 == 0x80) return _map(t & 0x0f);
    switch (t) {
      case 0xc0:
        return null;
      case 0xc2:
        return false;
      case 0xc3:
        return true;
      case 0xc4:
        return Uint8List.fromList(_take(_uint(1)));
      case 0xc5:
        return Uint8List.fromList(_take(_uint(2)));
      case 0xc6:
        return Uint8List.fromList(_take(_uint(4)));
      case 0xc7:
        return _ext(_uint(1));
      case 0xc8:
        return _ext(_uint(2));
      case 0xc9:
        return _ext(_uint(4));
      case 0xca:
        return _bd(4).getFloat32(0);
      case 0xcb:
        return _bd(8).getFloat64(0);
      case 0xcc:
        return _uint(1);
      case 0xcd:
        return _uint(2);
      case 0xce:
        return _uint(4);
      case 0xcf:
        return _uint(8);
      case 0xd0:
        return _bd(1).getInt8(0);
      case 0xd1:
        return _bd(2).getInt16(0);
      case 0xd2:
        return _bd(4).getInt32(0);
      case 0xd3:
        return _bd(8).getInt64(0);
      case 0xd4:
        return _ext(1);
      case 0xd5:
        return _ext(2);
      case 0xd6:
        return _ext(4);
      case 0xd7:
        return _ext(8);
      case 0xd8:
        return _ext(16);
      case 0xd9:
        return _str(_uint(1));
      case 0xda:
        return _str(_uint(2));
      case 0xdb:
        return _str(_uint(4));
      case 0xdc:
        return _list(_uint(2));
      case 0xdd:
        return _list(_uint(4));
      case 0xde:
        return _map(_uint(2));
      case 0xdf:
        return _map(_uint(4));
    }
    throw FormatException('bad msgpack type byte 0x${t.toRadixString(16)}');
  }
}
