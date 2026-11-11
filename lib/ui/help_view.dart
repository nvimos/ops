import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// The keys the app has, by where they work (PLAN.md "Keys" is the full draft).
const keyTable = [
  (
    'Everywhere',
    [
      ('Alt+] / Alt+[', 'next / previous mode'),
      ('Alt+1 … Alt+4', 'mode by its place on the rail'),
      ('Ctrl+B', 'expand / collapse the sidebar'),
      ('?', 'this list'),
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

Future<void> showKeys(BuildContext context) => showDialog<void>(context: context, builder: (c) => const KeysDialog());

class KeysDialog extends StatelessWidget {
  const KeysDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: C.surface,
    title: const Text('Keys', style: T.title),
    content: SizedBox(
      width: 460,
      child: ListView(
        shrinkWrap: true,
        children: [for (final (group, keys) in keyTable) _KeyGroup(title: group, keys: keys)],
      ),
    ),
    actions: [SmallButton('Close', onPressed: Navigator.of(context).pop)],
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
        SizedBox(width: 130, child: Text(keys, style: T.code)),
        Expanded(child: Text(what, style: T.small)),
      ],
    ),
  );
}
