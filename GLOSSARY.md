# Tern plugins

Plugins installed into Tern from this repository, and the vocabulary for judging how their UI looks next to Tern's own blocks.

## UI quality

**Native parity**:
The quality bar for a plugin's UI: a user cannot tell it from one of Tern's built-in blocks.
_Avoid_: Polish, consistent styling, native look

**Defect**:
A rendered flaw that is wrong under any taste, such as clipped content, misaligned edges or uneven spacing.
_Avoid_: Style bug, layout glitch

**Drift**:
A place where a plugin's UI differs from the equivalent built-in Tern control, such as a button whose cursor, height or hover differs.
_Avoid_: Inconsistency, mismatch

**Taste call**:
A visual choice that is neither a Defect nor Drift, decided by the owner's preference.
_Avoid_: Style tweak, nit

**Redline**:
One finding the owner raises after looking at a rendered plugin: a Defect, Drift or Taste call, with where it is.
_Avoid_: Feedback, review comment

## Building UI

**Native builder**:
A UI part Tern itself provides to plugins, the same one its built-in blocks use, such as a button, table or tabs strip.
_Avoid_: Host component, built-in widget

**Component**:
A UI part this repository owns for something no Native builder covers, assembled from Native builders.
_Avoid_: Widget, custom element, shared style
