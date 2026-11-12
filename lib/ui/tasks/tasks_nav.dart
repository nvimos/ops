import 'package:material_ui/material_ui.dart';

import '../../backend/models.dart';
import '../../tasks/browser.dart';
import '../theme.dart';
import '../widgets.dart';
import 'icons.dart';

/// The Tasks sidebar: project, running agents, Inbox, task views by status, sources, labels.
class TasksNav extends StatelessWidget {
  const TasksNav({
    super.key,
    required this.browser,
    required this.projectName,
    required this.scope,
    required this.loading,
    required this.jobs,
    required this.onCancelJob,
  });

  final TaskBrowser browser;
  final String projectName;
  final ScopeInfo scope;
  final bool loading;
  final List<Job> jobs;
  final ValueChanged<Job> onCancelJob;

  NavItem _item(NavTarget n, {Widget? lead, IconData icon = Icons.task_alt}) => NavItem(
    label: n.label,
    count: n.count,
    selected: browser.isCurrent(n),
    lead: lead ?? Icon(icon, size: 15, color: browser.isCurrent(n) ? C.text : C.muted),
    onTap: () => browser.go(n),
  );

  static IconData _sourceIcon(TView v) => switch (v) {
    TView.changes => Icons.description_outlined,
    TView.specs => Icons.account_tree_outlined,
    TView.milestones => Icons.flag_outlined,
    _ => Icons.history,
  };

  List<Widget> _taskItems() => [
    for (final n in browser.navTasks())
      switch (n.status) {
        'open' => _item(n),
        null => _item(n, icon: Icons.list),
        final s => _item(n, lead: StatusIcon(s, size: 13)),
      },
  ];

  @override
  Widget build(BuildContext context) {
    final inbox = NavTarget('Inbox', TView.inbox, count: browser.inboxCount);
    final labels = browser.navLabels();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 10),
      children: [
        ProjectHeader(name: projectName, loading: loading),
        if (scope.shown) ProjectScope(scope),
        for (final j in jobs) JobRow(job: j, onCancel: () => onCancelJob(j)),
        _item(inbox, icon: Icons.notifications_none),
        const SizedBox(height: 8),
        ..._taskItems(),
        const SizedBox(height: 10),
        for (final n in browser.navSources()) _item(n, icon: _sourceIcon(n.view)),
        if (labels.isNotEmpty)
          LabelsHeader(
            count: labels.length,
            open: browser.labelsOpen,
            byCount: browser.labelsByCount,
            onToggleOpen: browser.toggleLabelsOpen,
            onToggleSort: browser.toggleLabelSort,
          ),
        if (browser.labelsOpen)
          for (final n in labels) _item(n, icon: Icons.label_outline),
      ],
    );
  }
}

/// A sidebar entry: icon, label, count.
class NavItem extends StatelessWidget {
  const NavItem({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.lead,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Widget lead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverRow(
    selected: selected,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: Row(
      children: [
        lead,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: T.body.copyWith(color: selected ? C.text : const Color(0xFFC8CBD3)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text('$count', style: T.tiny),
      ],
    ),
  );
}

class NavSection extends StatelessWidget {
  const NavSection(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 16, 12, 6),
    child: Text(title, style: T.section),
  );
}

/// The LABELS header: a chevron that expands / collapses the list, how many labels there are, and
/// the sort, which a click on the title switches between name and task count.
class LabelsHeader extends StatelessWidget {
  const LabelsHeader({
    super.key,
    required this.count,
    required this.open,
    required this.byCount,
    required this.onToggleOpen,
    required this.onToggleSort,
  });

  final int count;
  final bool open, byCount;
  final VoidCallback onToggleOpen, onToggleSort;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 10, 12, 2),
    child: Row(
      children: [
        IconButton(
          tooltip: open ? 'Collapse the labels' : 'Expand the labels',
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          onPressed: onToggleOpen,
          icon: Icon(open ? Icons.expand_more : Icons.chevron_right, color: C.muted),
        ),
        Expanded(child: _title()),
      ],
    ),
  );

  Widget _title() => Tooltip(
    message: 'Click: sort by name / by number of tasks',
    child: InkWell(
      onTap: onToggleSort,
      child: Text.rich(
        TextSpan(
          text: 'LABELS',
          style: T.section,
          children: [
            TextSpan(text: '  $count', style: T.section.copyWith(color: C.text)),
            if (open) TextSpan(text: byCount ? '  BY COUNT' : '  BY NAME', style: T.section.copyWith(color: C.faint)),
          ],
        ),
      ),
    ),
  );
}

/// The project's initial in an accent square, its name, and a spinner while loading.
class ProjectHeader extends StatelessWidget {
  const ProjectHeader({super.key, required this.name, required this.loading});

  final String name;
  final bool loading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 12, 12),
    child: Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(5)),
          child: Text(
            name.isEmpty ? 'F' : name[0].toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.bg),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(name.isEmpty ? 'Folio' : name, style: T.title, overflow: TextOverflow.ellipsis)),
        if (loading) const Spinner(),
      ],
    ),
  );
}

/// What the scope line under the project header shows: where the planning comes from, this repo's
/// project there, and whether only its tasks show.
class ScopeInfo {
  const ScopeInfo({this.source, this.project, this.projectOnly = true, this.onToggle});

  /// The planning folder's name when it is outside the repo, else null.
  final String? source;
  final String? project;
  final bool projectOnly;
  final VoidCallback? onToggle;

  bool get shown => source != null || project != null;
}

/// "from nvimos-meta", and a pill that switches between this project's tasks and all of them.
class ProjectScope extends StatelessWidget {
  const ProjectScope(this.info, {super.key});

  final ScopeInfo info;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 12, 10),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (info.source != null) Text('from ${info.source}', style: T.small),
        if (info.project != null) _toggle(),
      ],
    ),
  );

  Widget _toggle() => Tooltip(
    message: 'a: this project / all projects',
    child: InkWell(
      onTap: info.onToggle,
      borderRadius: BorderRadius.circular(10),
      child: Pill(info.projectOnly ? info.project! : 'all projects', color: C.accent, filled: info.projectOnly),
    ),
  );
}

/// A running agent; a click cancels it.
class JobRow extends StatelessWidget {
  const JobRow({super.key, required this.job, required this.onCancel});

  final Job job;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '${job.label}\nclick to cancel',
    child: HoverRow(
      onTap: onCancel,
      padding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
      child: Row(
        children: [
          const Spinner(size: 13),
          const SizedBox(width: 10),
          Expanded(child: Text('Agent: ${job.label}', style: T.small, overflow: TextOverflow.ellipsis)),
        ],
      ),
    ),
  );
}

/// Title and count, the filter field, and the view's own action.
class TaskListHeader extends StatelessWidget {
  const TaskListHeader({
    super.key,
    required this.title,
    required this.count,
    required this.filter,
    required this.filterFocus,
    required this.onQuery,
    required this.action,
  });

  final String title;
  final int count;
  final TextEditingController filter;
  final FocusNode filterFocus;
  final ValueChanged<String> onQuery;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.border))),
    child: Row(
      children: [
        Flexible(child: Text(title, style: T.title, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text('$count', style: T.tiny),
        const Spacer(),
        Flexible(flex: 4, child: FilterField(controller: filter, focus: filterFocus, onChanged: onQuery)),
        if (action != null) ...[const SizedBox(width: 10), action!],
      ],
    ),
  );
}

class FilterField extends StatelessWidget {
  const FilterField({super.key, required this.controller, required this.focus, required this.onChanged});

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 220, maxHeight: 28),
    child: TextField(
      controller: controller,
      focusNode: focus,
      style: T.body,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Filter  /',
        prefixIcon: const Icon(Icons.search, size: 15, color: C.muted),
        prefixIconConstraints: const BoxConstraints(minWidth: 30),
        suffixIcon: ClearButton(controller: controller, onCleared: onChanged),
        suffixIconConstraints: ClearButton.constraints,
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
      ),
    ),
  );
}

class GroupByMenu extends StatelessWidget {
  const GroupByMenu({super.key, required this.value, required this.options, required this.onPick});

  final String value;
  final List<String> options;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Group by',
    color: C.surface2,
    onSelected: onPick,
    itemBuilder: (_) => [
      for (final g in options) PopupMenuItem(value: g, height: 32, child: Text('Group by $g', style: T.body)),
    ],
    child: Row(
      children: [
        const Icon(Icons.view_agenda_outlined, size: 15, color: C.muted),
        const SizedBox(width: 5),
        Text(value, style: T.small),
      ],
    ),
  );
}

/// The detail panel sliding in from the right; [child] null closes it.
class DetailPanel extends StatelessWidget {
  const DetailPanel({super.key, required this.width, required this.child});

  final double width;
  final Widget? child;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    width: child == null ? 0 : width,
    decoration: const BoxDecoration(color: C.surface, border: Border(left: BorderSide(color: C.border))),
    child: child == null
        ? const SizedBox.shrink()
        : ClipRect(
            child: OverflowBox(alignment: Alignment.topLeft, minWidth: width, maxWidth: width, child: child),
          ),
  );
}
