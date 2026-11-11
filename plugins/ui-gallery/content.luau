--!strict
local Kit = require("./kit")

local ui = tern.ui
local group, node = Kit.group, Kit.node

local TOKENS = { "muted", "dim", "strong", "em", "accent", "success", "warning", "error", "info", "pending", "code", "mono", "num", "ins", "del", "mark", "typo", "link" }

local RUST = [[use std::io;

fn main() {
    let name = "tern";
    let count: u32 = 42;
    // a comment
    println!("{} {}", name, count);
}]]

local SCORED = "alpha 0.9\nbeta 0.6\ngamma 0.3\ndelta 0.2\nepsilon 0.2\nzeta 0.9\neta 0.1\ntheta 0.4"

local DIFF = [[--- a/src/lib.rs
+++ b/src/lib.rs
@@ -1,6 +1,7 @@
 fn greet(name: &str) {
-    println!("Hello {}", name);
+    let line = format!("Hello, {}!", name);
+    println!("{}", line);
 }
 
 fn main() {
     greet("tern");
 }]]

local MARKDOWN = [[# Heading one
## Heading two

Prose with **bold**, *italic*, `inline code` and a [link](https://example.com).

> A blockquote that quotes something useful.

- First item
- Second item with `code`
  - Nested item

1. Numbered
2. Steps

| Name | State |
| --- | --- |
| nightly | ok |
| weekly | failed |

```lua
local x = 1
```

---

Done.]]

local ANSI = "\27[1mBold\27[0m \27[31mred\27[0m \27[32mgreen\27[0m \27[33myellow\27[0m \27[34mblue\27[0m \27[35mmagenta\27[0m \27[36mcyan\27[0m\n"
	.. "\27[4munderline\27[0m \27[7minverse\27[0m \27[38;5;208m256-color orange\27[0m \27[38;2;120;200;255mtruecolor sky\27[0m\n"
	.. "\27[90mgray\27[0m  \27[41m red bg \27[0m  \27[42m green bg \27[0m  \27[1;33;44m bold yellow on blue \27[0m"

local function spans(items: { string }): { any }
	local out = {}
	for _, t in items do
		table.insert(out, ui.span(t, t))
		table.insert(out, "  ")
	end
	return out
end

local Content: Kit.Section = {
	id = "content",
	label = "Content",
	build = function(s: Kit.State): { any }
		local cited = {
			{ t = "The lockfile drifted from package.json", cite = { title = "pnpm install, frozen lockfile", href = "https://pnpm.io/cli/install", snippet = "CI fails when the lockfile needs an update." } },
			" after the bump, and ",
			{ t = "CI refuses frozen installs", cite = { { title = "Frozen lockfile errors", href = "https://github.com/pnpm/pnpm/issues/7019" }, { title = "pnpm install", href = "https://pnpm.io/cli/install" } } },
			".",
		}
		return {
			group("Text: span tokens", {
				ui.text(spans(TOKENS)),
				ui.text({ ui.span("Page title", "title") }),
				ui.text({ ui.span("A shimmering span", "strong"), "  ", { t = "pulse", fx = "pulse" }, "  ", { t = "shimmer", fx = "shimmer" }, "  ", ui.span("strong error", "strong error") }),
			}),
			group("Keycaps (key span, kbd, button keys)", {
				ui.text({ ui.span("ctrl+r", "key"), "  ", ui.span("shift+enter", "key"), "  ", ui.span("cmd+k", "key"), "  ", ui.span("f5", "key"), "  ", ui.span("Esc to cancel", "key") }),
				ui.row({ node("kbd", { keys = { "cmd", "shift", "p" } }), node("kbd", { keys = { "ctrl", "o" } }), node("kbd", { keys = { "esc" } }), node("kbd", { keys = { "tab" } }), node("kbd", { keys = { "up", "down" } }) }),
			}),
			group("Link, path, citation", {
				ui.text({ ui.link("Documentation", "https://example.com"), "  ", ui.path("src/auth/session.ts"), "  ", ui.path("~/notes/plan.md"), "  ", ui.span("src/routes/users.ts", "path") }),
				node("text", { cite = "chip", spans = cited }),
				node("text", { cite = "pill", spans = cited }),
				node("text", { cite = "note", spans = cited }),
			}),
			group("Code: grammar, numbers, header, wrap", {
				node("code", { text = RUST, lang = "rust" }),
				node("code", { text = RUST, path = "src/main.rs", numbers = true, start = 1 }),
				node("code", { text = "let veryLongLine = someFunction(argumentNumberOne, argumentNumberTwo, argumentNumberThree, argumentNumberFour, argumentNumberFive);", lang = "ts", wrap = true }),
			}),
			group("Code: marks, ranges, heat, wash", {
				node("code", {
					text = RUST,
					lang = "rust",
					numbers = true,
					marks = { { line = 4, tone = "error", ranges = { { 15, 21 } } }, { line = 5, tone = "warning" }, { line = 7, tone = "accent" } },
				}),
				node("code", {
					text = SCORED,
					numbers = true,
					overview = true,
					marks = { { line = 1, tone = "accent", heat = 0.9, wash = { 0.9, 0.3 } }, { line = 2, heat = 0.6, wash = { 0.6, 0.2 } }, { line = 6, heat = 0.9 }, { line = 8, heat = 0.4, wash = { 0.4 } } },
				}),
			}),
			group("Code: folds, excerpts (nums), preview", {
				node("code", { text = SCORED, numbers = true, folds = { { from = 3, to = 5, label = "… [lines 3-5]", note = "3 lines below the cutoff", tone = "error" } } }),
				node("code", { text = "fn a() {}\nfn b() {}\nfn c() {}", lang = "rust", numbers = true, nums = { 12, 13, 48 } }),
				node("code", { text = RUST, lang = "rust", numbers = true, preview = { lines = 3 } }),
			}),
			group("Diff: unified, split", {
				node("card", { head = "src/lib.rs", icon = "diff", inset = true }, { node("diff", { text = DIFF, path = "src/lib.rs", mode = "unified" }) }),
				node("card", { head = "src/lib.rs, split", icon = "split", inset = true }, { node("diff", { text = DIFF, path = "src/lib.rs", mode = "split" }) }),
			}),
			group("Markdown", { node("md", { text = MARKDOWN }) }),
			group("ANSI output", { node("ansi", { text = ANSI }) }),
			group("Image, JSON", {
				node("image", { blob = s.img[1], alt = "Gradient", max = { h = "6lines" } }),
				node("image", { builtin = "omp", alt = "omp", w = 48, h = 48 }),
				node("json", { value = { name = "highlight_batch", ts = 62213.5, ok = true, args = { stream = 0, lines = 70 }, tags = { "a", "b" } }, open = 1 }),
			}),
			group("Empty, stats, key/value", {
				node("empty", { variant = "inline", tone = "error", title = "Could not load runs", text = "The server did not answer" }, { ui.button("Retry", { size = "sm" }) }),
				ui.stats({ { label = "Runs", value = "24", sub = "2 failed" }, { label = "p95", value = "182 ms", tone = "warning" }, { label = "Errors", value = "0.4%", tone = "error", sub = "last 15 min" }, { label = "Uptime", value = "99.9%", tone = "success" } }),
				ui.kv({ { "context", "prod" }, { "namespace", "default" }, { "image", ui.span("registry/app:4.2.0", "mono") } }),
				node("kv", { layout = "inline", items = { { k = "context", v = "prod" }, { k = "namespace", v = "default" }, { k = "pods", v = "12" } } }),
			}),
			group("Rule: line, note, pin", {
				ui.rule(""),
				ui.rule("Older"),
				node("rule", { variant = "note", icon = "history", label = "Compacted", time = "14:05" }),
				node("rule", { variant = "pin", icon = "pin", label = "Plan approved", time = "14:12" }),
			}),
			group("Diagnostic, test summary, overflow", {
				ui.diagnostic({
					severity = "error",
					code = "E0308",
					message = "mismatched types: expected `u32`, found `&str`",
					path = "src/main.rs",
					line = 5,
					col = 22,
					snippet = { 4, "    let name = \"tern\";\n    let count: u32 = \"42\";\n    println!(\"{}\", count);" },
					notes = { "expected due to this type annotation" },
					suggestions = { { "parse the string", 5, "    let count: u32 = \"42\".parse().unwrap();" } },
				}, "/work"),
				ui.diagnostic({ severity = "warning", code = "unused", message = "unused variable: `name`", path = "src/main.rs", line = 4, col = 9 }, "/work"),
				ui.test_summary(21, 2, 1, "8.4s"),
				ui.overflow(14),
			}),
		}
	end,
}

return Content
