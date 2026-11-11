--!strict
local Kit = require("./kit")

local ui = tern.ui
local group, node, at = Kit.group, Kit.node, Kit.at

local AUTO = "Message: auto, the agent chat"
local BUBBLE = "Message: bubble, the messenger"
local FLAT = "Message: flat, the team thread"
local THREAD = "thread"

type Reaction = { text: string, count: number, on: boolean? }

local function avatar(key: string, props: { [string]: any }): any
	props.key = key
	return node("avatar", props)
end

local function md(text: string): any
	return node("md", { text = text })
end

-- A click on a chip flips it at once; the event is mirrored here so a rebuild keeps it.
local function reactions(s: Kit.State, key: string, base: { Reaction }): { any }
	local out = {}
	for _, r in base do
		local flipped = s.v[`react.{key}.{r.text}`]
		local on = if flipped == nil then r.on == true else flipped == true
		local count = r.count - (if r.on == true then 1 else 0) + (if on then 1 else 0)
		table.insert(out, { text = r.text, count = count, on = on })
	end
	return out
end

local TRACE_LINES = {
	{ id = "think", icon = "clock", title = "Thought for 5s", status = "done", took = 5000 },
	{ id = "v", icon = "terminal", title = "Ran", target = "pnpm --version", status = "done", took = 420 },
	{ id = "diff", icon = "terminal", title = "Ran", target = "git diff --stat HEAD~1", status = "done", took = 180, open = true },
	{ id = "inst", icon = "terminal", title = "Failed", target = "pnpm install --frozen-lockfile", status = "error", took = 3100, detail = "ERR_PNPM_OUTDATED_LOCKFILE" },
	{
		id = "src",
		icon = "globe",
		title = "Used 2 sources",
		status = "done",
		sources = {
			{ title = "pnpm install", href = "https://pnpm.io/cli/install", site = "pnpm.io" },
			{ title = "Frozen lockfile in CI", href = "https://github.com/pnpm/pnpm/issues/1890", site = "github.com" },
		},
	},
}

local LIVE_LINES = {
	{ id = "a", icon = "search", title = "Searched", target = "lockfile drift", status = "done", took = 900 },
	{ id = "b", icon = "terminal", title = "Running", target = "pnpm install", status = "running", age = 4000 },
	{ id = "c", icon = "terminal", title = "Test", target = "pnpm test", status = "pending" },
}

local FRAMES = {
	{
		fn = "resolveUser",
		file = "src/auth/session.ts",
		line = 42,
		col = 13,
		code = { start = 40, lines = { "  const s = await load(token);", "  if (!s) return null;", "  return users.get(s.user.id);", "}" } },
	},
	{ fn = "Layer.handle", file = "node_modules/express/lib/router/layer.js", line = 95, col = 5, app = false },
	{ fn = "next", file = "node_modules/express/lib/router/route.js", line = 149, col = 13, app = false },
	{ fn = "main", file = "src/index.ts", line = 8, col = 3, code = { start = 6, lines = { "async function main() {", "  const app = express();", "  app.use(session);", "}" } } },
}

local ERROR = { type = "TypeError", message = "Cannot read properties of undefined (reading 'id')" }

local PLAN = {
	{ id = "dir", prompt = "Direction", required = true, choices = { { value = "deleg", label = "Delegation" }, { value = "ask", label = "Question prompts" } } },
	{
		id = "detail",
		prompt = "What should we prototype next?",
		description = "Pick one, or write your own.",
		other = { placeholder = "Another answer…" },
		choices = {
			{ value = "deleg", label = "Delegation", detail = "Work moving to a specialist" },
			{ value = "ask", label = "Question prompts", detail = "Choices while the UI waits" },
		},
	},
	{ id = "scope", prompt = "Include", multi = true, choices = { "SDK API", "Book page", "Lua builders" } },
}

local function messages(s: Kit.State): { any }
	local copyRetry = { { act = "copy" }, { act = "retry", title = "Regenerate" } }
	return {
		group(AUTO, {
			node("col", { key = THREAD, gap = "none" }, {
				node("message", { key = "q", side = "end", time = "14:02" }, { md("Why does the frozen install fail?") }),
				node("message", { key = "a", author = "omp", time = "14:02", avatar = at(AUTO, THREAD, "a", "av") }, {
					avatar("av", { icon = "provider:anthropic", size = "sm", title = "omp" }),
					md("The lockfile was not updated after the version bump. Run `pnpm install` and commit the result."),
				}),
				node("message", { key = "a2", author = "omp", continued = true, actions = copyRetry, reveal = "always" }, {
					ui.code("pnpm install\ngit add pnpm-lock.yaml", "bash"),
				}),
				node("message", { key = "q2", side = "end", status = "Sending…", pending = true }, { md("Thanks, trying it now") }),
			}),
		}),
		group(BUBBLE, {
			node("col", { key = THREAD, gap = "none" }, {
				node("message", {
					key = "b1",
					variant = "bubble",
					author = "Sarah",
					time = "14:03",
					avatar = at(BUBBLE, THREAD, "b1", "av"),
					reactions = reactions(s, "b1", { { text = "♥", count = 2 }, { text = "👍", count = 1 } }),
				}, { avatar("av", { text = "Sarah Moss", status = "success" }), md("Are we still on for the review?") }),
				node("message", { key = "b2", variant = "bubble", continued = true, reactions = reactions(s, "b2", { { text = "🎉", count = 1, on = true } }) }, { md("I have the notes ready") }),
				node("message", { key = "b3", variant = "bubble", side = "end" }, { md("Yes, 15:00 works") }),
				node("message", { key = "b4", variant = "bubble", side = "end", continued = true, status = "Read 14:03" }, { md("I will bring the lockfile fix") }),
			}),
		}),
		group(FLAT, {
			node("col", { key = THREAD, gap = "none" }, {
				node("message", { key = "f1", variant = "flat", author = "Sarah Moss", time = "14:02", avatar = at(FLAT, THREAD, "f1", "av") }, {
					avatar("av", { text = "Sarah Moss", size = "lg" }),
					md("The migration is green on dev1. I rebased and **force-pushed** the branch."),
				}),
				node("message", {
					key = "f2",
					variant = "flat",
					author = "omp",
					time = "14:05",
					avatar = at(FLAT, THREAD, "f2", "av"),
					reactions = reactions(s, "f2", { { text = "👀", count = 2 }, { text = "🚀", count = 1 } }),
					actions = { { act = "react", icon = "plus", title = "Add reaction" }, { act = "reply", icon = "message", title = "Reply" }, { act = "copy" }, { act = "more" } },
					reveal = "always",
				}, {
					avatar("av", { icon = "provider:anthropic", size = "lg", title = "omp" }),
					md("Checked: 24 runs, 0 failed."),
					ui.code("pnpm test --run\n24 passed", "bash"),
				}),
				node("message", { key = "f3", variant = "flat", continued = true, time = "14:06" }, { md("Merging after lunch.") }),
			}),
		}),
	}
end

local function parts(s: Kit.State): { any }
	local thumb = s.img[1]
	return {
		group("Attachment: chip, states, actions", {
			node("attachment", { key = "att1", name = "homepage-feedback.pdf", size = 2400000, actions = { { act = "download", icon = "download", title = "Download" } } }),
			node("attachment", { key = "att2", name = "runs-2026-10.csv", state = "uploading", progress = 0.62, removable = true }),
			node("attachment", { key = "att3", name = "notes.md", state = "processing" }),
			node("attachment", { key = "att4", name = "spec.pdf", state = "error", error = "Too large", removable = true }),
			node("attachment", { key = "att5", name = "shot.png", size = 183000, blob = thumb }),
		}),
		group("Attachment: tile and pill", {
			ui.row({
				node("attachment", { key = "tile1", variant = "tile", name = "shot-1.png", blob = thumb, removable = true }),
				node("attachment", { key = "tile2", variant = "tile", name = "homepage-feedback.pdf" }),
				node("attachment", { key = "tile3", variant = "tile", name = "spec.pdf", state = "error", removable = true }),
				node("attachment", { key = "pill1", variant = "pill", name = "report.pdf", removable = true }),
				node("attachment", { key = "pill2", variant = "pill", name = "main.rs", removable = true }),
			}),
		}),
		group("Avatar: sizes, variants, status", {
			ui.row({
				node("avatar", { text = "Cara Alvarez", size = "xs" }),
				node("avatar", { text = "Cara Alvarez", size = "sm" }),
				node("avatar", { text = "Cara Alvarez", size = "md" }),
				node("avatar", { text = "Cara Alvarez", size = "lg" }),
				node("avatar", { text = "Ben Ortiz", seed = "ben@acme.dev", status = "success" }),
				node("avatar", { text = "Eve Park", status = "warning" }),
				node("avatar", { text = "Ada Lim", status = "error" }),
				node("avatar", {}),
			}),
			ui.row({
				node("avatar", { variant = "square", text = "ci", seed = "acme/ci" }),
				node("avatar", { variant = "square", text = "web", seed = "acme/web", size = "lg" }),
				node("avatar", { icon = "provider:anthropic", size = "lg", title = "Anthropic" }),
				node("avatar", { icon = "provider:openai", size = "lg", title = "OpenAI" }),
				node("avatar", { icon = "bolt", size = "lg" }),
				node("avatar", { blob = thumb, size = "lg", text = "Picture" }),
			}),
		}),
		group("Avatars: stack, max, label", {
			node("avatars", { items = { { text = "Cara Alvarez" }, { text = "Ben Ortiz" }, { text = "Eve Park" }, { text = "Ada Lim" }, { text = "Sam Moss" }, { text = "Joy Kim" }, { text = "Lee Roy" } }, max = 4, label = "7 reviewers" }),
			node("avatars", { items = { { text = "Cara Alvarez" }, { text = "Ben Ortiz" }, { variant = "square", text = "ci", seed = "acme/ci" } }, size = "lg" }),
		}),
	}
end

local function agent(s: Kit.State): { any }
	return {
		group("Trace: rail, settled and live", {
			node("trace", { key = "tr1", lines = TRACE_LINES }, {
				node("code", { key = "diff", lang = "text", text = "package.json | 2 +-\n1 file changed, 1 insertion(+), 1 deletion(-)" }),
			}),
			node("trace", { key = "tr2", title = "Fixing the lockfile", status = "running", age = 6000, lines = LIVE_LINES }),
		}),
		group("Trace: summary and reasoning card", {
			node("trace", { key = "tr3", variant = "summary", status = "done", took = 12000, lines = TRACE_LINES, open = true }),
			node("trace", { key = "tr4", variant = "summary", status = "error", took = 12000, lines = TRACE_LINES }),
			node("trace", { key = "tr5", variant = "card", status = "running", age = 4000, sources = { { title = "pnpm install", href = "https://pnpm.io/cli/install", site = "pnpm.io" } } }, {
				node("text", { text = "The frozen install fails because the lockfile was not updated after the version bump." }),
			}),
			node("trace", { key = "tr6", variant = "card", status = "done", took = 4000 }, { node("text", { text = "Settled reasoning keeps its prose." }) }),
		}),
		group("Tool call: states and approval", {
			node("tool", { key = "t1", name = "bash", title = "Ran", target = "pnpm install --frozen-lockfile", targetKind = "command", status = "done", took = 3100, collapsible = true }, {
				ui.code("Lockfile is up to date\nDone in 3.1s", "text"),
			}),
			node("tool", { key = "t2", name = "read", title = "Read", target = "src/auth/session.ts:40-60", targetKind = "path", status = "running", age = 1200 }),
			node("tool", { key = "t3", name = "bash", title = "Ran", target = "pnpm test", targetKind = "command", status = "error", exit = 1, took = 8400, badges = { { text = "flaky", tone = "warning" } } }),
			node("tool", { key = "t4", name = "bash", title = "Deploy", target = "pnpm deploy --prod", targetKind = "command", status = "ask" }),
			node("tool", { key = "t5", name = "web", title = "Fetch", target = "https://pnpm.io/cli/install", status = "ask", confirm = "strip", ask = { text = "Allow this request?" } }),
		}),
		group("Stacktrace: frames, split, mono", {
			node("stacktrace", { key = "st1", error = ERROR, frames = FRAMES }),
			node("stacktrace", { key = "st2", variant = "split", lang = "typescript", error = ERROR, frames = FRAMES }),
			node("stacktrace", { key = "st3", variant = "mono", error = ERROR, frames = FRAMES }),
		}),
		group("System message (rule: line, note, pin)", {
			node("rule", { label = "Yesterday" }),
			node("rule", { variant = "line", icon = "history", label = "Checkpoint 3", time = "14:02" }),
			node("rule", { variant = "note", icon = "history", label = "Compacted 4 messages", time = "14:05" }),
			node("rule", { key = "ck", variant = "note", icon = "history", label = "Checkpoint 4", time = "14:09", ["end"] = at("System message (rule: line, note, pin)", "ck", "restore") }, {
				ui.button("Restore", { key = "restore", size = "sm" }),
			}),
			node("rule", { variant = "pin", icon = "pin", label = "Plan approved", time = "14:12", tone = "success" }),
		}),
	}
end

local function prompts(s: Kit.State): { any }
	local items = { { id = "explain", text = "Explain this error" }, { id = "test", text = "Write a test for resolveUser" }, { id = "lint", text = "Fix the 3 lint warnings", detail = "src/user.ts" }, { id = "pr", text = "Open a PR", detail = "branch is ahead 2", icon = "branch" } }
	return {
		group("Suggestions: chips, rows, cards", {
			node("suggestions", { key = "sg1", items = items }),
			node("suggestions", { key = "sg2", variant = "rows", items = items }),
			node("suggestions", { key = "sg3", variant = "cards", items = items }),
		}),
		group("Questions: steps, inline, list", {
			node("questions", { key = "qs1", step = 1, answers = { dir = "deleg" }, items = PLAN }, { node("input", { key = "detail.other", variant = "field", placeholder = "Another answer…" }) }),
			node("questions", { key = "qs2", variant = "inline", step = 1, answers = { dir = "deleg" }, items = PLAN }, { node("input", { key = "detail.other", variant = "field", placeholder = "Another answer…" }) }),
			node("questions", { key = "qs3", variant = "list", step = 1, answers = { dir = "deleg" }, items = PLAN }, { node("input", { key = "detail.other", variant = "field", placeholder = "Another answer…" }) }),
		}),
	}
end

-- A composer is one framed editor: the attachment tray over it, Attach and Send inside its ring.
local function composer(s: Kit.State): { any }
	return {
		group("Composer: tray, attach, send", {
			ui.row({
				node("attachment", { key = "cp1", variant = "pill", name = "report.pdf", removable = true }),
				node("attachment", { key = "cp2", variant = "pill", name = "main.rs", removable = true }),
			}),
			node("editor", {
				key = "cmp",
				text = Kit.val(s, "cmp", "Review the lockfile change and summarize the risk."),
				variant = "field",
				placeholder = "Message omp",
				buttons = { { act = "attach", icon = "file-plus", title = "Attach" }, { act = "send", text = "Send", variant = "primary", keys = { "enter" } } },
			}),
		}),
	}
end

local Chat: Kit.Section = {
	id = "chat",
	label = "Chat",
	build = function(s: Kit.State): { any }
		local out = messages(s)
		for _, g in parts(s) do
			table.insert(out, g)
		end
		for _, g in agent(s) do
			table.insert(out, g)
		end
		for _, g in prompts(s) do
			table.insert(out, g)
		end
		for _, g in composer(s) do
			table.insert(out, g)
		end
		return out
	end,
}

return Chat
