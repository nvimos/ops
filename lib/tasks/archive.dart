import 'markdown.dart';
import 'model.dart';
import 'parse.dart';

/// A living spec file split into the part before the requirements, the requirement blocks, and
/// the part after the Requirements section.
class _SpecParts {
  _SpecParts(this.head, this.blocks, this.tail);
  final List<String> head;
  final List<(String, List<String>)> blocks; // name, lines (without trailing blank lines)
  final List<String> tail;

  List<String> join() {
    final out = [...head];
    while (out.isNotEmpty && out.last.trim().isEmpty) {
      out.removeLast();
    }
    for (final (_, lines) in blocks) {
      out
        ..add('')
        ..addAll(lines);
    }
    if (tail.isNotEmpty) {
      out.add('');
      out.addAll(tail);
    }
    return _trimBlank(out);
  }
}

List<String> _trimBlank(List<String> lines) {
  final out = [...lines];
  while (out.isNotEmpty && out.last.trim().isEmpty) {
    out.removeLast();
  }
  return out;
}

_SpecParts _split(List<String> lines) {
  final sections = parseSections(lines);
  final req = findSection(sections, (t) => t == 'requirements', level: 2);
  if (req == null) {
    return _SpecParts([..._trimBlank(lines), '', '## Requirements'], [], []);
  }
  final reqs = parseRequirements(lines, req.start + 1, req.end);
  final firstReq = reqs.isEmpty ? req.end : reqs.first.$1.start;
  return _SpecParts(lines.sublist(0, firstReq), [
    for (final (r, raw) in reqs) (r.name, _trimBlank(raw)),
  ], lines.sublist(req.end));
}

/// A new living spec for a capability.
List<String> newSpec(String capability, String changeId) => [
  '# $capability Specification',
  '',
  '## Purpose',
  '',
  'Created by archiving $changeId; describe the purpose.',
  '',
  '## Requirements',
];

/// Merge a change's deltas for one capability into its spec (or a new one): ADDED appends (or
/// replaces a requirement of the same name), MODIFIED replaces, REMOVED deletes. RENAMED is left
/// to the CLI.
List<String> mergeDeltas(List<String>? spec, String capability, String changeId, List<Delta> deltas) {
  final parts = _split(spec ?? newSpec(capability, changeId));
  int find(String name) => parts.blocks.indexWhere((b) => b.$1.toLowerCase() == name.toLowerCase());
  for (final d in deltas) {
    final i = find(d.requirement.name);
    switch (d.op) {
      case DeltaOp.added || DeltaOp.modified:
        final block = (d.requirement.name, _trimBlank(d.lines));
        if (i >= 0) {
          parts.blocks[i] = block;
        } else {
          parts.blocks.add(block);
        }
      case DeltaOp.removed:
        if (i >= 0) parts.blocks.removeAt(i);
      case DeltaOp.renamed:
        break;
    }
  }
  return parts.join();
}

/// Where an archived change goes: `openspec/changes/archive/<yyyy-mm-dd>-<id>`.
String archiveDir(Change c, DateTime date) =>
    'openspec/changes/archive/${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}-${c.id}';
