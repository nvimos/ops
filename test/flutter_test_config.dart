import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/temp_dirs.dart';

/// Runs around every test file: the temp repos and dirs it made are deleted when it is done, so
/// %TEMP% doesn't fill up with a repo (and a git fsmonitor daemon) per test.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  tearDownAll(removeTempDirs);
  await testMain();
}
