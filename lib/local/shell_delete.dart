/// The Windows shell's own delete, called straight from Dart: `SHFileOperationW`
/// in `shell32.dll`, the call Explorer makes. With [recycle] the items go to the
/// Recycle Bin; without, they are removed for good. No process, no script.
library;

import 'dart:ffi';
import 'dart:isolate';

/// `SHFILEOPSTRUCTW` as the 64-bit shell reads it.
final class _ShFileOp extends Struct {
  external Pointer<Void> hwnd;

  @Uint32()
  external int func;

  external Pointer<Uint16> from;
  external Pointer<Uint16> to;

  @Uint16()
  external int flags;

  @Int32()
  external int anyAborted;

  external Pointer<Void> nameMappings;
  external Pointer<Uint16> title;
}

const _foDelete = 3;
const _fofSilent = 0x4;
const _fofNoConfirmation = 0x10;
const _fofAllowUndo = 0x40;
const _fofNoErrorUi = 0x400;

/// What a shell delete answers: 0 is done, anything else is its error code.
/// A cancelled operation answers [cancelled].
const cancelled = -1;

/// Delete [paths] (absolute, backslashes) with the shell; returns its code.
/// Runs on its own isolate so a big folder cannot hold the window.
Future<int> shellDelete(List<String> paths, {required bool recycle}) =>
    Isolate.run(() => _shellDeleteNow(paths, recycle: recycle));

int _shellDeleteNow(List<String> paths, {required bool recycle}) {
  final ole = DynamicLibrary.open('ole32.dll');
  final alloc = ole.lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('CoTaskMemAlloc');
  final free = ole.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('CoTaskMemFree');
  final operation = DynamicLibrary.open('shell32.dll')
      .lookupFunction<Int32 Function(Pointer<_ShFileOp>), int Function(Pointer<_ShFileOp>)>('SHFileOperationW');

  // The list is every path then a zero, and one more zero at the very end.
  final units = [for (final path in paths) ...[...path.codeUnits, 0], 0];
  final from = alloc(units.length * 2).cast<Uint16>();
  for (var i = 0; i < units.length; i++) {
    from[i] = units[i];
  }
  final op = alloc(sizeOf<_ShFileOp>()).cast<_ShFileOp>();
  op.ref
    ..hwnd = nullptr
    ..func = _foDelete
    ..from = from
    ..to = nullptr
    ..flags = _fofSilent | _fofNoConfirmation | _fofNoErrorUi | (recycle ? _fofAllowUndo : 0)
    ..anyAborted = 0
    ..nameMappings = nullptr
    ..title = nullptr;
  try {
    final code = operation(op);
    if (code != 0) return code;
    return op.ref.anyAborted != 0 ? cancelled : 0;
  } finally {
    free(from.cast());
    free(op.cast());
  }
}

/// The shell's error code in words; the codes are `DE_*` of `shellapi.h`.
String shellDeleteMessage(int code) => switch (code) {
      cancelled => 'the delete was cancelled',
      0x78 => 'access denied',
      0x79 || 0x81 => 'the path is too long',
      0x7C => 'Windows refused: the path is invalid, or the file is in use by another program',
      _ => 'Windows could not delete it (shell error 0x${code.toRadixString(16).toUpperCase()})',
    };
