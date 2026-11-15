# Bugs

## `gi` does not return to the directory filter after moving down the list

Directories mode: `gi` from the list does not focus the filter field, so the typed keys are not
going into the input.

### Steps

1. Alt+[ / Alt+] to move through the modes until Directories is shown.
2. Press `gi`. Focus goes to the directory filter input.
3. Press Down. Focus moves into the directory list and the list scrolls.
4. Press `gi` again.

### Expected

Focus goes back to the directory filter input, and typing goes into it.

### Actual

Focus stays in the directory list (or somewhere else). The filter does not take the keys, so typing
does not go into the input.

### Notes

- The widget tests do not reproduce it: after the same key sequence the focus lands on the filter.
  The failing case is probably specific to how the list is focused in the running app.

## The +/- change counts in the file list do not line up

Changes mode, file list: each file row shows its change counts as a green `+N` (additions) and a red
`−N` (deletions). The greens and reds do not line up down the list. When a file has no deletions, its
green count takes the place of the red column, so the greens are not always under the greens.

### What was asked

- The plus and minus signs, and the numbers after them, are separate items. The sign of each is
  coloured 60% background and 40% its colour (green for `+`, red for `−`); the number keeps the plain
  colour.
- The numbers line up vertically, assuming at least two digits.
- A row without additions or without deletions still has its place for that count, left empty. The
  greens sit under the greens and the reds under the reds. A missing red does not let the green take its
  place.
- Not a real table: a mental model only.

### What was done

- `lib/ui/file_tree.dart`: each file row has a sign cell and a two-digit number cell for additions,
  then the same for deletions. The cells keep their width when the count is 0.
- `lib/ui/text_width.dart` (new): `textWidth`, moved out of `resizable_pane.dart` so the file list can
  use it.
- `lib/ui/resizable_pane.dart`: the pane's width calculation reserves the same count width for each file.

### Status

Not confirmed in the running app. The file-tree tests pass, but they don't check the alignment. The
previous version right-aligned the whole count inside one slot, so the sign moved with the number of
digits. The current version fixes the sign cells, and the numbers sit in fixed cells.

## Escape after Shift+P or Shift+C leaves the keyboard where Alt+[ / Alt+] stop working

element:

  Root Focus Scope  >  FocusTraversalGroup  >  View Scope  >  Shortcuts: <Default WidgetsApp Shortcuts>  >  Shortcuts: <Default Text Editing Shortcuts>  >  FocusTraversalGroup  >  Shortcuts: <Shortcut Registrar>  >  Focus  >  Navigator Scope  >  FocusTraversalGroup  >  Navigator  >  _ModalScopeState<dynamic> Focus Scope


Shift+P (head picker, Pull request) and Shift+C (branch switcher, Changes) open a picker and put the
keyboard in its field. Pressing Escape then leaves the focus on an unlabeled item, and from there the
Alt+[ and Alt+] mode shortcuts do not work.

### Steps

1. Press Shift+P (or Shift+C).
2. Press Escape.

### Expected

Focus goes to a labelled place (the mode's pane, or the rail), and Alt+[ / Alt+] still switch modes.

### Actual

Focus lands on an unlabeled item. Alt+[ and Alt+] do nothing from there.

### Notes

- Escape in the picker first closes its list. Escape with the list already closed leaves the field.
  The focus then goes to a node with no debug label, which the shell does not handle.
