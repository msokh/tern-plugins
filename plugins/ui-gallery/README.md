# UI Gallery

A block that renders Tern's native UI builders, to check a plugin's UI against what Tern itself draws. Run `UI Gallery: Open` from the palette, or `node scripts/preview.mjs ui-gallery` to save a PNG per tab.

Tabs built: **Action, Form, Form Controls, Feedback & Status, Navigation, Table & List, Overlay, Chat, Container, Content, Layout**. `host.luau` lists the tabs; `chat.luau`, `container.luau`, `content.luau` and `layout.luau` hold one each, and `kit.luau` holds the shared helpers (`group` keys a card by its title so `at(title, key, ...)` can name a child id, as `message` `avatar` and card `end` need). A node a preview step must reach carries a `role` (`gallery.*`), which Tern exposes as `data-role`.

`host.luau` is a flat list of sections. A controlled node gets `key = <name>`; `event` writes `change`, `select` and `toggle` back into `state.v[name]`, so switches, selects, tabs, pagers, tables and lists answer a click. Text typing (keys and focus) is not wired.

Page inset: the gallery wraps each tab in `./ui/page` (`styles = ["ui/ui.css"]`).

Marks: `native` = the kind was drawn in a PNG that was looked at (the PNG is named); `approx` = closest native, difference stated; `gap` = no native kind.

Prop shapes seen working: `tabs` takes `active` (not `selected`), event `{ev="select", id="main.<key>", item}`; `input`/`editor` want `variant = "field"`; `select`/`switch`/`slider`/`calendar`/`date`/`pager` send `change` with `value`; `select` and `date` also send `toggle`.

## Coverage of the Astryx catalog (107 components: 79 native, 23 approx, 5 gap)

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
| Chat Composer | `editor` with attach and send `buttons`, an attachment `pill` tray over it (shot `chat-composer`) | native |
| Chat Layout | `scroll stick="end"` plus `message` nodes | approx: no layout kind |
| Chat Message, Metadata, System Message, Tool Calls | `message` auto, bubble, flat with reactions, status, actions; `rule` line, note, pin; `tool` (shots `chat-1`..`chat-6`) | native |
| Card | `ui.card` | native |
| Carousel | `carousel` peek, arrows, strip with image blobs (shot `container-2`) | native |
| Collapsible | `card` and `section` with `collapsible`, `preview` | native |
| Clickable Card, Selectable Card | `card` with `actions.click` and `selected`; a click picks the card (shot `container-card-picked`) | native |
| Avatar, Avatar Group | `avatar`, `avatars` (shot `chat-3`) | native |
| Blockquote, Heading, Rich Text View | `md` draws headings and a quoted block (shot `content-3`) | native |
| Citation | `text` `cite` chip, pill, note (shot `content-1`) | native |
| Code, Code Block | `code` grammar, numbers, marks, heat, folds, nums, preview; span `code` (shot `content-2`) | native |
| Empty State | `empty` center, inline, drop | native |
| Icon | `icon` | native |
| Kbd | `kbd`, button `keys` | native |
| Markdown, Text | `md`, `text` (shots `content-1`, `content-3`) | native |
| Thumbnail, Token | `image`, `attachment`, `badge` | approx |
| Timer, Timestamp | `elapsed` | approx: counts up, no absolute timestamp |
| Badge | `ui.badge` | native |
| Banner | `card` with `tone="warning"` | approx: tint is faint, no banner kind |
| Info Tip | `icon` with `title` and with `hovercard` (shots `feedback-infotip`, `feedback-infocard`) | native: the `title` tooltip is clipped at the window's left edge, see Defects |
| Progress Bar | `ui.progress`, `meter` | native |
| Skeleton | `skeleton` | native |
| Spinner | `spinner` | native |
| Status Dot | table cell `dot` | native |
| Calendar | `calendar` month, range, week | native |
| Checkbox Input | `lib/ui/checkbox` (native `list` of `item` rows, `selection`/`check` icons); one option or a list; clicks drive it (shot `controls-components-clicked`) | approx: icon box, not a drawn checkbox |
| Radio List | `lib/ui/radio` (native `meter` ring + `text` rows) | approx: the mark is a ring, not a dot in a ring |
| Complex Selector | `select` with `detail`, `group`, `icon` | approx |
| Date Input | `date` | native |
| Date Range Input | `date range=true`, popover and a picked range (shots `controls-daterange-open`, `controls-daterange-picked`) | native |
| Date Time Input | `date` has no time of day | approx |
| Time Input | none | gap |
| Field | `field` stacked, grid, row | native |
| File Input | `empty variant="drop"` + `attachment` | approx |
| Multi Selector | `lib/ui/multiselect` (chips + native `menu` of `checked` rows; shots `controls-multi-open`, `controls-multi-picked`) | approx: the menu closes after each pick |
| Number Input | `input` with `stepper`, `unit` (shot `form`); the stepper adds or subtracts 5 | native |
| Power Search, Tokenizer | `input` with `icon`, `keys`, `clear`; no chips | approx |
| Selector | `select` field, quiet, sm, disabled | native |
| Slider | `slider` default, accent, range | native |
| Switch | `switch` default, compact, segment | native |
| Text Area | `editor` | native |
| Text Input | `input` | native |
| Typeahead | `select search=true` | native |
| Typeahead Item | `select` option row: icon, label, detail, group header, disabled row (shot `controls-typeahead-open`) | native |
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
| Top Nav Mega Menu | `nav variant="links"` with sub-items opens a two-column panel (shot `navigation-mega-open`) | native |
| Featured Card | a panel entry: icon tile, title, one-line description | approx: no hero card |
| Top Nav Menu | `menubar` with a submenu (shot `navigation-menubar-submenu`), `nav` pills menu (shot `navigation-pills-menu-open`) | native |
| Bottom Sheet | `overlay side="bottom"` (shot `overlay-sheet`) | native |
| Bottom Sheet Switcher (deprecated) | none | approx |
| Command Palette | `picker size="md"` with groups, hits, key column, Close and Run (shot `overlay-palette`) | native |
| Dialog | `overlay modal` with `foot` | native |
| Drawer | `overlay side="right"` (shot `overlay-drawer`) | native |
| Hover Card | `hovercard` (shot `overlay-hovercard`) | native |
| Tooltip | `title` (shots `overlay-tooltip`, `feedback-infotip`) | native: clipped at the window's left edge, see Defects |
| Lightbox | `image` zoom | approx |
| Overlay | `overlay` | native |
| Popover | `overlay anchor={node=}` under its button (shot `overlay-popover`) | native |
| Toast | `cx:toast` from the block's `event` (shot `overlay-toast`) | native |
| List | `list` + `item` | native |
| Metadata List | `ui.kv` | native |
| Overflow List | `breadcrumb max` | native |
| Table | `table` selectable, sort, multi | native |
| Table Selection Toolbar | `table` selection bar | native |
| Tree List | `ui.tree` | native |
| VisuallyHidden | `aria` prop | approx |

## Defects in Tern's rendering

- Tooltip from `title`: the bubble sits left of its target and is cut off at the window's left edge (`overlay-tooltip`: "uns the automation now"; `feedback-infotip`: "s again when the lockfile changes"). The `hovercard` of the same nodes is placed correctly (`overlay-hovercard`).

## Gaps

- Time Input: `date` has no time of day. Needs Tern.
- Rich Text Editor, Auto-Link Plugin, Rich Text Toolbar: needs Tern.
- Aspect Ratio: no ratio prop. Needs Tern.

## Fixed gallery bugs

- Feedback tab: `ui.table` rows take `cells` as an array, one cell per column; the old map keyed by column id drew headers only.
- Action tab: the split button chevron is the icon `chev` (`chev-down` is not an icon name).
- Overlay tab: the Toast button calls `cx:toast` from `event`; the toast shows at the window's bottom center, outside the block's own surface.
- Content tab: `ui.diagnostic` takes `suggestions` as positional `{message, firstLine, code}` rows.
