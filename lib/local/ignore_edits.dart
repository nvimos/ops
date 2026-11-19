/// The pure edits of an ignore file: Dirname, Flip, the line a written rule landed on, and how a
/// write changed the list. No git, no widgets, so the shapes are unit-tested on their own.
library;

import '../backend/models.dart';

/// Why a line cannot be edited, in the words the menus and tooltips use.
abstract final class IgnoreRefusal {
  /// A comment or a blank line: Dirname has nothing to move.
  static const notPositive = 'dirname only works on positive rules';

  /// A negation (`!…`): the user edits it by hand instead.
  static const negation = 'please edit negation rules manually';

  /// A parent that is only wildcards (`**`, `[a-z]`): it would ignore far too much.
  static const wildcard = 'please edit wildcard rules manually';

  /// No folder above the rule (`*.log`, `/x.log`, `build/`).
  static const noParent = 'no folder above this rule';

  /// Flip only changes rules; comments and blank lines are not rules.
  static const notRule = 'flip only works on rules';
}

/// What a [IgnoreEdits.dirname] or [IgnoreEdits.flip] came to: the new [text], or the [refusal].
class IgnoreRuleEdit {
  const IgnoreRuleEdit.rule(String this.text) : refusal = null;
  const IgnoreRuleEdit.refused(String this.refusal) : text = null;

  final String? text;
  final String? refusal;

  bool get ok => refusal == null;
}

/// The rule line in [line], trimmed, or null for a comment or a blank line.
///
/// Git's first column decides: `#` starts a comment, so `\#` is a rule for a name that starts with
/// `#`. Leading spaces are trimmed like the local rules engine does (`IgnoreRules.dirname`).
String? ruleText(String line) {
  final text = line.trim();
  if (text.isEmpty || text.startsWith('#')) return null;
  return text;
}

/// The pure line edits of an ignore file.
abstract final class IgnoreEdits {
  /// Take [line]'s rule one folder up, as Purrage's Dirname does: `/a/b/x.log` becomes `/a/b/`,
  /// `/a/b/` becomes `/a/`. The refusals name why (see [IgnoreRefusal]).
  static IgnoreRuleEdit dirname(String line) {
    final text = ruleText(line);
    if (text == null) return const IgnoreRuleEdit.refused(IgnoreRefusal.notPositive);
    if (text.startsWith('!')) return const IgnoreRuleEdit.refused(IgnoreRefusal.negation);
    final anchored = text.startsWith('/');
    final body = text.substring(anchored ? 1 : 0).replaceFirst(RegExp(r'/+$'), '');
    final parts = body.split('/');
    if (body.isEmpty || parts.length < 2) return const IgnoreRuleEdit.refused(IgnoreRefusal.noParent);
    final kept = parts.sublist(0, parts.length - 1).join('/');
    // `**`, `[a-z]` and the like name no folder of their own: a rule there would ignore far too much.
    // Escaped glob characters are literal names and do count.
    final literal = kept
        .replaceAllMapped(RegExp(r'\\.'), (_) => 'x')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'[*?]'), '')
        .trim();
    if (literal.isEmpty) return const IgnoreRuleEdit.refused(IgnoreRefusal.wildcard);
    return IgnoreRuleEdit.rule('${anchored ? '/' : ''}$kept/');
  }

  /// Toggle the literal leading `!` of [line]'s rule: a positive rule becomes a negation and back.
  /// A comment or a blank line is refused; an escaped `\!` is a positive rule, so it gains the `!`.
  static IgnoreRuleEdit flip(String line) {
    final text = ruleText(line);
    if (text == null || text == '!') return const IgnoreRuleEdit.refused(IgnoreRefusal.notRule);
    return IgnoreRuleEdit.rule(text.startsWith('!') ? text.substring(1) : '!$text');
  }

  /// The 1-based line of [rule] in [text], exactly as the file holds it, or null.
  static int? lineOfRule(String text, String rule) {
    final lines = text.split(RegExp(r'\r\n|\n'));
    for (var i = 0; i < lines.length; i++) {
      if (lines[i] == rule) return i + 1;
    }
    return null;
  }

  /// The line to centre after a write: the first pattern that [added] says was new and that is now
  /// in [text]. Null when every pattern was already there (a duplicate writes nothing new).
  static int? lineAfterWrite(String text, List<String> patterns, {required List<bool> added}) {
    for (var i = 0; i < patterns.length && i < added.length; i++) {
      if (!added[i]) continue;
      final line = lineOfRule(text, patterns[i]);
      if (line != null) return line;
    }
    return null;
  }
}

/// How a write changed the list: rows that came back ([gained]) and rows that left it ([lost]).
class IgnoreEffect {
  const IgnoreEffect(this.gained, this.lost);

  /// Count the untracked rows that left (`lost`) or appeared (`gained`) between two statuses. Only
  /// untracked rows are counted: ignore rules never apply to tracked files.
  factory IgnoreEffect.between(List<StatusFile> before, List<StatusFile> after) {
    final was = {for (final f in before) if (f.untracked) f.path};
    final now = {for (final f in after) if (f.untracked) f.path};
    return IgnoreEffect(now.difference(was).length, was.difference(now).length);
  }

  final int gained, lost;

  /// "2 files now ignored", "1 file back in the list", or both; null when nothing moved.
  String? get message {
    final parts = [
      if (lost > 0) '$lost ${lost == 1 ? 'file' : 'files'} now ignored',
      if (gained > 0) '$gained ${gained == 1 ? 'file back' : 'files back'} in the list',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
