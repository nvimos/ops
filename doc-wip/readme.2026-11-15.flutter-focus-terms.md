# Is "root focus" the typical Flutter name for the app's top-level key handler?

No. "Root focus" was an informal description, not a Flutter term.

## Flutter's terms

- `FocusNode`: the object that holds focus.
- `FocusScopeNode`: a node that groups focus nodes and remembers which child in it last had focus.
- `FocusManager.instance.rootScope`: the top of the whole focus tree.
- `Focus` widget: attaches a node to the tree and can set `onKeyEvent`.

## The app's `shell` node

It is a `Focus` with `onKeyEvent`, near the top of the tree, labelled `shell` in `lib/ui/shell.dart`.
Flutter has no single name for that role. Code usually calls it an app-level key handler or a
top-level `Focus`. `Shortcuts` and `Actions` are the built-in way to do the same job.
