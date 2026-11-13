#!/usr/bin/env node
// usage: node scripts/preview.mjs <plugin> [--out DIR] [--keep]
// Renders a plugin in the running Tern window from fixtures and saves one PNG per `shot` step.
// The plugin runs as a renamed copy (<id>-preview) with its own KV store and fixture files, so the
// installed plugin and its real settings are never touched. Steps come from
// scripts/preview/<plugin>/preview.json: `shot NAME`, `click-text TEXT`, or any `tern ctl` command.
// The window is shared with whoever uses it, so the block is focused again before every step.
import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, rmdirSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const plugin = args.find((a) => !a.startsWith("--") && args[args.indexOf(a) - 1] !== "--out");
const outIndex = args.indexOf("--out");
if (!plugin) {
	console.error("usage: node scripts/preview.mjs <plugin> [--out DIR] [--keep]");
	process.exit(2);
}
const fixtures = join(root, "scripts", "preview", plugin);
const spec = JSON.parse(readFileSync(join(fixtures, "preview.json"), "utf8"));
const out = outIndex >= 0 ? args[outIndex + 1] : join(tmpdir(), "tern-preview", "shots", plugin);
const work = join(tmpdir(), "tern-preview", plugin);
const id = `${plugin}-preview`;
const copy = join(work, id);
const home = join(work, "home");
const surface = `[data-surface^="plugin.${id}."]`;

const tern = (...a) => execFileSync("tern", a, { encoding: "utf8" }).trim();
const ctl = (...a) => {
	const reply = JSON.parse(tern("ctl", ...a));
	if (!reply.ok) throw new Error(`tern ctl ${a.join(" ")}: ${reply.error}`);
	return reply;
};
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

function walk(dir) {
	return readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? walk(join(dir, n)) : [join(dir, n)]));
}

function blocks() {
	const found = [];
	const visit = (x) => {
		if (Array.isArray(x)) x.forEach(visit);
		else if (x && typeof x === "object") {
			if (x.id != null && typeof x.program === "string" && x.program.startsWith(`${id}.`)) found.push(String(x.id));
			Object.values(x).forEach(visit);
		}
	};
	visit(JSON.parse(tern("inspect", "--json")));
	return found;
}

// One window is shared, so concurrent runs would focus and click each other's blocks. The lock also
// guards the work and data directories below, so it is taken before either is touched. It names its
// owner by pid: a live owner is never displaced, a dead one is, and only the owner releases it.
const lock = join(tmpdir(), "tern-preview", ".lock");
const owner = join(lock, "pid");
const alive = (pid) => {
	try {
		process.kill(pid, 0);
		return true;
	} catch (e) {
		return e.code === "EPERM";
	}
};
const ownerOf = () => {
	try {
		return Number(readFileSync(owner, "utf8"));
	} catch {
		return NaN;
	}
};
mkdirSync(dirname(lock), { recursive: true });
for (const started = Date.now(); ; sleep(500)) {
	try {
		mkdirSync(lock);
		writeFileSync(owner, String(process.pid));
		break;
	} catch (e) {
		if (e.code !== "EEXIST") throw e;
		const pid = ownerOf();
		const held = statSync(lock, { throwIfNoEntry: false });
		const orphaned = held && (Number.isInteger(pid) ? !alive(pid) : Date.now() - held.mtimeMs > 30_000);
		if (orphaned) rmSync(lock, { recursive: true, force: true });
		else if (Date.now() - started > 600_000) throw new Error(`another preview has held ${lock} for 10 minutes`);
	}
}
process.once("exit", () => {
	if (ownerOf() === process.pid) rmSync(lock, { recursive: true, force: true });
});

rmSync(work, { recursive: true, force: true });
cpSync(join(root, "plugins", plugin), copy, { recursive: true, dereference: true });
for (const file of walk(copy)) {
	if (!/\.(luau|css|toml)$/.test(file)) continue;
	let text = readFileSync(file, "utf8");
	text = text.replace(new RegExp(`(["'\`])${plugin}\\.`, "g"), `$1${id}.`);
	if (file.endsWith("plugin.toml")) text = text.replace(/^id = ".*"$/m, `id = "${id}"`);
	for (const [from, to] of Object.entries(spec.replace ?? {})) text = text.split(from).join(to.replaceAll("$HOME_DIR", home));
	writeFileSync(file, text);
}
if (existsSync(join(fixtures, "home"))) cpSync(join(fixtures, "home"), home, { recursive: true });
mkdirSync(home, { recursive: true });

const data = join(dirname(tern("plugin", "dir")), "plugin-data", id);
rmSync(data, { recursive: true, force: true });
if (existsSync(join(fixtures, "kv.json"))) {
	mkdirSync(data, { recursive: true });
	const now = Math.floor(Date.now() / 1000);
	const kv = readFileSync(join(fixtures, "kv.json"), "utf8").replace(/"\$NOW([+-]\d+)?"/g, (_, d) => String(now + Number(d ?? 0)));
	writeFileSync(join(data, "kv.json"), kv);
}

mkdirSync(out, { recursive: true });
// `tern ctl shot` writes under target/ in the window's working directory, the home directory.
const shotRoot = join(process.env.HOME, "target");
const hadShotRoot = existsSync(shotRoot);
tern("plugin", "link", copy);
try {
	sleep(1000);
	ctl("plugins", "run", `plugin.${id}.${spec.open}`);
	sleep(1500);
	const [block] = blocks();
	if (!block) throw new Error(`plugin.${id}.${spec.open} opened no block`);
	for (const step of spec.steps) {
		tern("focus", block);
		sleep(300);
		if (step.startsWith("shot ")) {
			const name = step.slice(5);
			const shot = ctl("shot", `${plugin}-${name}`);
			const dump = ctl("dump", surface);
			const box = dump.elements.find((e) => e.visible)?.rect;
			const png = join(out, `${name}.png`);
			const inHome = (p) => (p.startsWith("/") ? p : join(process.env.HOME, p));
			cpSync(inHome(shot.png), png);
			rmSync(inHome(shot.png), { force: true });
			rmSync(inHome(shot.layout), { force: true });
			if (!box) throw new Error(`shot ${name}: the block is not on screen`);
			const scale = dump.header.viewport.deviceScaleFactor;
			const [x, y, w, h] = box.map((v) => Math.round(v * scale));
			execFileSync("sips", ["-c", String(h), String(w), "--cropOffset", String(y), String(x), png, "--out", png], { stdio: "ignore" });
			console.log(png);
		} else if (step.startsWith("click-text ")) {
			const text = step.slice(11);
			const hits = ctl("tree", `${surface} *`).nodes.filter((n) => n.text?.trim() === text && n.rect[2] > 0);
			const hit = hits.find((n) => n.tag === "button") ?? hits.sort((a, b) => a.rect[2] * a.rect[3] - b.rect[2] * b.rect[3])[0];
			if (!hit) throw new Error(`no visible element in the block reads "${text}"`);
			const [x, y, w, h] = hit.rect;
			ctl("click", String(Math.round(x + w / 2)), String(Math.round(y + h / 2)));
			sleep(500);
		} else {
			ctl(...step.split(" "));
			sleep(400);
		}
	}
} finally {
	if (!args.includes("--keep")) {
		for (const block of blocks()) tern("close", block);
		tern("plugin", "unlink", id);
		rmSync(data, { recursive: true, force: true });
	}
	if (!hadShotRoot) for (const dir of [join(shotRoot, "shots", "tern", "live"), join(shotRoot, "shots", "tern"), join(shotRoot, "shots"), shotRoot]) try { rmdirSync(dir); } catch {}
}
