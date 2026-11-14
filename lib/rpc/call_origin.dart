/// What a request is and where in the app it came from, for the network monitor's list of slow
/// requests. Session data only: nothing here is stored.
class CallOrigin {
  const CallOrigin({required this.what, required this.from, required this.detail});

  /// The request in the backend's words: `nvimos.git.diff_file`, or the RPC method (`nvim_get_api_info`).
  final String what;

  /// The app's functions that asked, nearest first, as `ChangesState._loadDiff ← _ChangesViewState._commit`.
  final String from;

  /// The first argument of the call when it is text (a path, a branch), shortened.
  final String detail;
}

/// Describes the request [method] with [args], made from [stack].
CallOrigin describeRequest(String method, List<Object?> args, StackTrace stack) {
  var what = method;
  var detail = '';
  if (method == 'nvim_exec_lua' && args.isNotEmpty) {
    final m = _luaCall.firstMatch('${args[0]}');
    if (m != null) what = '${m[1]}.${m[2]}';
    final lua = args.length > 1 && args[1] is List ? args[1]! as List : const [];
    if (lua.isNotEmpty && lua.first is String) detail = _short(lua.first! as String);
  }
  return CallOrigin(what: what, from: callersOf(stack), detail: detail);
}

final _luaCall = RegExp(r"require\('([\w.]+)'\)\.(\w+)");
final _frame = RegExp(r'^#\d+\s+(.+?) \(package:nvimos_poc/([^:]+):(\d+):\d+\)', multiLine: true);

/// The frames that are plumbing: the client, the backend wrapper, the timing helpers.
bool _plumbing(String file) => file.startsWith('rpc/') || file == 'backend/backend.dart' || file.startsWith('timing/');

/// Up to [max] of the app's functions in [stack], nearest first, skipping the request plumbing.
String callersOf(StackTrace stack, {int max = 3}) {
  final names = <String>[];
  for (final m in _frame.allMatches('$stack')) {
    if (_plumbing(m[2]!)) continue;
    final name = m[1]!.replaceAll(RegExp(r'\.<anonymous closure>|\.<fn>|\.<\w+ closure>'), '').replaceAll('new ', '');
    if (names.isNotEmpty && names.last == name) continue;
    names.add(name);
    if (names.length == max) break;
  }
  return names.isEmpty ? '(unknown)' : names.join(' ← ');
}

String _short(String s) {
  final one = s.replaceAll('\n', ' ');
  return one.length > 60 ? '${one.substring(0, 59)}…' : one;
}
