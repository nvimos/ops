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
    ],
  ),
  (
    'Pull request',
    [
      ('gb / gh', 'base / head picker'),
      ('gs', 'swap base and head'),
      (']f / [f', 'next / previous file'),
      ('v', 'unified / side-by-side'),
      ('zw', 'line wrapping'),
      ('zR / zM', 'expand / collapse all folders'),
      ('Esc', 'back from one commit to all commits'),
    ],
  ),
  (
    'Tasks',
    [
      ('j / k, Enter, Esc', 'move, open, close'),
      ('/', 'filter'),
      ('c / s / p', 'new task, cycle status, cycle priority'),
      ('Ctrl+K', 'command palette'),
    ],
  ),
  (
    'Directories',
    [
      ('j / k, Enter', 'move, make it the Active Directory'),
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
