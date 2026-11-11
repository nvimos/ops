import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// The keys the app has, by where they work (PLAN.md "Keys" is the full draft).
const keyTable = [
  (
    'Everywhere',
    [
      ('Alt+] / Alt+[', 'next / previous mode'),
      ('Alt+1 … Alt+5', 'mode by its place on the rail'),
      ('Ctrl+B', 'expand / collapse the sidebar'),
      ('?', 'this list (the Help mode)'),
      ('Tab / Shift+Tab', 'next / previous pane'),
    ],
  ),
  (
    'Any list',
    [
      ('j / k, arrows', 'next / previous item'),
      ('gg / G', 'first / last item'),
      ('Ctrl+D / Ctrl+U', 'half a page down / up'),
      ('Enter', 'open or pick the item'),
      ('o', 'open the item in Neovim'),
    ],
  ),
  (
    'Pull request',
    [
      ('gb / gh', 'base / head picker'),
      ('gs', 'swap base and head'),
      (']f / [f', 'next / previous file'),
      (']c / [c', 'next / previous hunk'),
      ('h / l', "fold / unfold the file's folder"),
      ('zR / zM', 'expand / collapse all folders'),
      ('v', 'unified / side-by-side'),
      ('zw', 'line wrapping'),
      ('Enter on a commit', 'show only that commit'),
      ('Esc', 'back from one commit to all commits'),
    ],
  ),
  (
    'Changes',
    [
      (']c / [c', 'next / previous hunk'),
      ('-', 'stage or unstage the hunk, or the file'),
      ('s / u', 'stage / unstage'),
      ('X', 'discard (asks first)'),
      ('cc', 'write the commit message'),
      ('Ctrl+Enter', 'commit (in the message)'),
      ('Esc', 'back from the message to the files'),
    ],
  ),
  (
    'Tasks',
    [
      ('/', 'filter'),
      ('Esc', 'close the detail panel'),
      ('c / s / p', 'new task, cycle status, cycle priority'),
      ('Ctrl+K', 'command palette'),
    ],
  ),
  (
    'Directories',
    [
      ('Enter', 'make it the Active Directory'),
      ('/', 'filter'),
      ('n', 'New Neovim per directory'),
    ],
  ),
];

/// The Help mode: every key the app has, by where it works.
class HelpView extends StatelessWidget {
  const HelpView({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PaneHeader(title: Text('Keys')),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          itemCount: keyTable.length,
          itemBuilder: (context, i) => _KeyGroup(title: keyTable[i].$1, keys: keyTable[i].$2),
        ),
      ),
    ],
  );
}

class _KeyGroup extends StatelessWidget {
  const _KeyGroup({required this.title, required this.keys});

  final String title;
  final List<(String, String)> keys;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(title.toUpperCase(), style: T.section),
      ),
      for (final (key, what) in keys) _KeyRow(keys: key, what: what),
    ],
  );
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.keys, required this.what});

  final String keys, what;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(width: 160, child: Text(keys, style: T.code)),
        Expanded(child: Text(what, style: T.small)),
      ],
    ),
  );
}
