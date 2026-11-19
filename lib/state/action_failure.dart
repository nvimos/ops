import 'dart:io';

import '../local/git_repo.dart';

/// One failed user action, with everything a person needs to see why.
///
/// Built where the failure is caught (the action knows its own parameters) and
/// handed to the notice bar and the Log, so both say the same thing.
class ActionFailure {
  const ActionFailure({
    required this.summary,
    required this.detail,
    this.code,
    this.origin,
    this.error = true,
  });

  /// One line, for the notice and the Log row.
  final String summary;

  /// The full story: origin, parameters, the command line, the tool's own text.
  final String detail;

  /// `exit 128`, `errno 5` — the failure in the tool's own terms.
  final String? code;

  /// `Changes.stage -> LocalBackend.stage` and so on.
  final String? origin;

  /// False for a report of something that worked: the Log keeps both, the notice
  /// bar only shows failures.
  final bool error;

  /// Wrap a backend error with the action it broke and how that action ran.
  /// `Session.run` already turns exceptions into text, so [fromText] is the
  /// common path; [fromError] is for a caller that still has the exception.
  factory ActionFailure.fromError(
    Object error, {
    required String origin,
    String? summary,
    Map<String, Object?> params = const {},
    String? command,
  }) {
    final lines = <String>['origin: $origin'];
    if (params.isNotEmpty) {
      lines.addAll(params.entries.map((entry) => '${entry.key}: ${entry.value}'));
    }
    if (command != null) lines.add('command: $command');

    String? code;
    var message = error.toString();
    if (error is GitException) {
      message = error.message;
      if (error.detail != null) lines.add(error.detail!);
    } else if (error is ProcessException) {
      code = 'exit ${error.errorCode}';
      message = '${error.message} (${error.executable})';
    } else if (error is FileSystemException) {
      final os = error.osError;
      code = os == null ? null : 'errno ${os.errorCode}';
      message = '${os?.message ?? error.message} — ${error.path ?? ''}';
    }
    if (code != null) lines.add('code: $code');
    lines.add('error: $message');

    return ActionFailure(
      summary: summary ?? _firstLine(message),
      detail: lines.join('\n'),
      code: code,
      origin: origin,
    );
  }

  /// Wrap the text a backend returned, keeping git's own words.
  factory ActionFailure.fromText(
    String text, {
    required String origin,
    String? summary,
    Map<String, Object?> params = const {},
    String? command,
  }) {
    final lines = <String>['origin: $origin'];
    if (params.isNotEmpty) {
      lines.addAll(params.entries.map((entry) => '${entry.key}: ${entry.value}'));
    }
    if (command != null) lines.add('command: $command');
    lines.add('error: $text');
    return ActionFailure(
      summary: summary ?? _firstLine(text),
      detail: lines.join('\n'),
      origin: origin,
    );
  }

  /// A failure made of many skipped rows, for a selection that partly worked.
  factory ActionFailure.fromSkips({
    required String origin,
    required String summary,
    required List<String> skipped,
    Map<String, Object?> params = const {},
  }) {
    final lines = <String>[
      'origin: $origin',
      ...params.entries.map((entry) => '${entry.key}: ${entry.value}'),
      'skipped ${skipped.length}:',
      ...skipped.map((line) => '  $line'),
    ];
    return ActionFailure(summary: summary, detail: lines.join('\n'), origin: origin);
  }

  /// A report of something that worked: the Log keeps it, the notice bar does not.
  factory ActionFailure.done({
    required String summary,
    required String detail,
    String? origin,
  }) =>
      ActionFailure(summary: summary, detail: detail, origin: origin, error: false);

  static String _firstLine(String text) {
    final line = text.split(RegExp(r'\r?\n')).firstWhere((line) => line.trim().isNotEmpty, orElse: () => text);
    return line.length > 200 ? '${line.substring(0, 197)}…' : line;
  }
}
