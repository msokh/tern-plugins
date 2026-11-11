# UI Gallery

A block that renders Tern's native UI builders, to check a plugin's UI against what Tern itself draws. Run `UI Gallery: Open` from the palette, or `node scripts/preview.mjs ui-gallery` to save a PNG per tab.

Tabs built: **Action, Form, Form Controls, Feedback & Status, Navigation, Table & List, Overlay, Chat, Container, Content, Layout**. `host.luau` lists the tabs; `chat.luau`, `container.luau`, `content.luau` and `layout.luau` hold one each, and `kit.luau` holds the shared helpers (`group` keys a card by its title so `at(title, key, ...)` can name a child id, as `message` `avatar` and card `end` need).

`host.luau` is a flat list of sections. A controlled node gets `key = <name>`; `event` writes `change`, `select` and `toggle` back into `state.v[name]`, so switches, selects, tabs, pagers, tables and lists answer a click. Text typing (keys and focus) is not wired.

Marks: `native` = the kind was drawn in a PNG that was looked at; `native-unverified` = built or documented in `docs.stencil.so/tern/elements/` but not seen; `approx` = closest native, difference stated; `gap` = no native kind.

Prop shapes seen working: `tabs` takes `active` (not `selected`), event `{ev="select", id="main.<key>", item}`; `input`/`editor` want `variant = "field"`; `select`/`switch`/`slider`/`calendar`/`date`/`pager` send `change` with `value`; `select` and `date` also send `toggle`.

## Coverage of the Astryx catalog (107 components: 60 native, 17 native-unverified, 22 approx, 8 gap)

| Astryx | Tern | Mark |
|---|---|---|
| Button | `ui.button` | native |
| Button Group | `buttons` joined | native |
| Dropdown Menu | `menu` trigger and open menu (shot `action-menu`) | native |
| Icon Button | `ui.button("", {icon})` | native |
| Link | `ui.link`, `ui.path` | native |
| More Menu | `menu` with `icon`, `trigger="quiet"` | native |
| Segmented Control | `tabs` segmented | native |
| Toggle Button | `button` with `on` | native |
| Toggle Button Group | `buttons` of `on` buttons | native |
| Toolbar | `buttons` toolbar | native |
| Chat Composer | `editor` with `buttons` (seen cut at the edge) | native-unverified |
| Chat Layout | `scroll stick="end"` plus `message` nodes | approx: no layout kind |
| Chat Message, Metadata, System Message, Tool Calls | `message` auto, bubble, flat with reactions, status, actions; `rule` line, note, pin; `tool` (shots `chat-1`..`chat-6`) | native |
| Card | `ui.card` | native |
| Carousel | `carousel` peek, arrows, strip with image blobs (shot `container-2`) | native |
| Collapsible | `card` and `section` with `collapsible`, `preview` | native |
| Clickable Card, Selectable Card | `card` with `actions.click` and `selected`; a click picks the card (shot `container-card-picked`) | native |
| Avatar, Avatar Group | `avatar`, `avatars` (shot `chat-3`) | native |
| Blockquote, Heading, Rich Text View | `md`, `text` spans (`title`, `strong`) | approx: no quote or heading kind |
| Citation | `text` `cite` | native-unverified |
| Code, Code Block | `code` grammar, numbers, marks, heat, folds, nums, preview; span `code` (shot `content-2`) | native |
| Empty State | `empty` center, inline, drop | native |
| Icon | `icon` | native |
| Kbd | `kbd`, button `keys` | native |
| Markdown, Text | `md`, `text` | native-unverified |
| Thumbnail, Token | `image`, `attachment`, `badge` | approx |
| Timer, Timestamp | `elapsed` | approx: counts up, no absolute timestamp |
| Badge | `ui.badge` | native |
| Banner | `card` with `tone="warning"` | approx: tint is faint, no banner kind |
| Info Tip | `icon` with `title` | native-unverified (hover not driven) |
| Progress Bar | `ui.progress`, `meter` | native |
| Skeleton | `skeleton` | native |
| Spinner | `spinner` | native |
| Status Dot | table cell `dot` | native |
| Calendar | `calendar` month, range, week | native |
| Checkbox Input, Radio List | no native kind; `el` input is banned by `ui.mjs check`; a Component from `button on` rows could cover it | gap |
| Complex Selector | `select` with `detail`, `group`, `icon` | approx |
| Date Input | `date` | native |
| Date Range Input | `date range=true`, field drawn, picking not driven | native-unverified |
| Date Time Input, Time Input | `date` has no time of day | gap for Time Input; approx for Date Time Input |
| Field | `field` stacked, grid, row | native |
| File Input | `empty variant="drop"` + `attachment` | approx |
| Multi Selector | none | gap |
| Number Input | `input` with `stepper`, `unit` | native-unverified |
| Power Search, Tokenizer | `input` with `icon`, `keys`, `clear`; no chips | approx |
| Selector | `select` field, quiet, sm, disabled | native |
| Slider | `slider` default, accent, range | native |
| Switch | `switch` default, compact, segment | native |
| Text Area | `editor` | native |
| Text Input | `input` | native |
| Typeahead | `select search=true` | native |
| Typeahead Item | `select` option row | native-unverified |
| Rich Text Editor, Auto-Link Plugin, Toolbar | none | gap: needs Tern |
| App Shell, Layout, Grid | `split`, `row`/`col` with `basis`, `wrap` | approx: no grid |
| Aspect Ratio | none | gap |
| Divider | `ui.rule`, `rule` variants | native |
| Form Layout | `field variant="grid"` | native |
| Resize Handle | `split` | native |
| Scrollable Area | `scroll` bar, fade, stick end (shot `layout-3`) | native |
| Section | `ui.section`, `section` collapsible | native |
| Stack | `col`, `row` with `gap`, `align`, `justify`, `wrap` (shot `layout-2`) | native |
| Breadcrumbs | `breadcrumb` chevron, path | native |
| Outline | `tree` | approx |
| Pagination | `pager` range, pages, more | native |
| Side Nav | `nav` pills | native |
| Stepper | row of `badge` | approx |
| Tab List | `tabs` underline | native |
| Top Nav | `nav links`, `menubar` | native |
| Top Nav Mega Menu, Featured Card, Menu | `nav` items with sub-items, `menubar` | native-unverified |
| Bottom Sheet | `overlay side="bottom"` | native-unverified |
| Bottom Sheet Switcher (deprecated) | none | approx |
| Command Palette | `picker` | native-unverified |
| Dialog | `overlay modal` with `foot` | native |
| Drawer | `overlay side="right"` | native-unverified |
| Hover Card, Tooltip | `hovercard`, `title` props | native-unverified |
| Lightbox | `image` zoom | approx |
| Overlay | `overlay` | native |
| Popover | `overlay anchor={node=}` | native-unverified |
| Toast | `cx:toast` from the block's `event` (shot `overlay-toast`) | native |
| List | `list` + `item` | native |
| Metadata List | `ui.kv` | native |
| Overflow List | `breadcrumb max` | native |
| Table | `table` selectable, sort, multi | native |
| Table Selection Toolbar | `table` selection bar | native |
| Tree List | `ui.tree` | native |
| VisuallyHidden | `aria` prop | approx |

## Gaps

- Checkbox Input, Radio List: no native kind. A lib/ui Component built from `button on` rows can cover it.
- Multi Selector: no native kind. A Component from `menu` items with `checked` can cover it.
- Time Input: `date` has no time of day. Needs Tern.
- Rich Text Editor, Auto-Link Plugin, Rich Text Toolbar: needs Tern.
- Aspect Ratio: no ratio prop. Needs Tern.

## Fixed gallery bugs

- Feedback tab: `ui.table` rows take `cells` as an array, one cell per column; the old map keyed by column id drew headers only.
- Action tab: the split button chevron is the icon `chev` (`chev-down` is not an icon name).
- Overlay tab: the Toast button calls `cx:toast` from `event`; the toast shows at the window's bottom center, outside the block's own surface.
- Content tab: `ui.diagnostic` takes `suggestions` as positional `{message, firstLine, code}` rows.
