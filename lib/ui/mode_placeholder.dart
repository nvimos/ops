import 'package:material_ui/material_ui.dart';

import 'mode_rail.dart';
import 'widgets.dart';

/// A mode on the rail whose view is not built yet: what it will be, and that it is coming.
class ModePlaceholder extends StatelessWidget {
  const ModePlaceholder(this.mode, {super.key});

  final Mode mode;

  @override
  Widget build(BuildContext context) => Empty('${mode.label}: ${mode.explain}.\nNot built yet.');
}
