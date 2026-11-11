#!/usr/bin/env node
// usage: node scripts/ui.mjs sync | check
// sync copies lib/ui into plugins/<p>/ui for every plugin that requires "./ui/...".
// check fails when a copy differs from lib/ui or a plugin bypasses the shared Components.
import { cpSync, existsSync, readdirSync, readFileSync, rmSync, statSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const lib = join(root, "lib", "ui");
const pluginsDir = join(root, "plugins");

function files(dir) {
	if (!existsSync(dir)) return [];
	return readdirSync(dir).flatMap((name) => {
		const path = join(dir, name);
		return statSync(path).isDirectory() ? files(path) : [path];
	});
}

const plugins = readdirSync(pluginsDir)
	.map((name) => join(pluginsDir, name))
	.filter((dir) => existsSync(join(dir, "plugin.toml")));

function own(plugin) {
	const vendored = join(plugin, "ui");
	return files(plugin).filter((f) => !f.startsWith(vendored + "/") && !f.includes("/tests/"));
}

function usesUi(plugin) {
	return own(plugin).some((f) => f.endsWith(".luau") && /require\("\.\/ui\//.test(readFileSync(f, "utf8")));
}

function syncDrift(plugin) {
	const copy = join(plugin, "ui");
	const want = files(lib).map((f) => relative(lib, f)).sort();
	const have = files(copy).map((f) => relative(copy, f)).sort();
	const drift = [];
	for (const name of new Set([...want, ...have])) {
		const a = join(lib, name);
		const b = join(copy, name);
		if (!existsSync(a) || !existsSync(b) || readFileSync(a, "utf8") !== readFileSync(b, "utf8")) drift.push(name);
	}
	return drift;
}

const RULES = [
	{ ext: ".luau", re: /\bui\.el\s*\(/g, why: "builds a raw element; use a Native builder or a Component from ./ui" },
	{ ext: ".css", re: /\.sf-[\w-]+/g, why: "restyles Tern's own classes" },
	{ ext: ".css", re: /(?<![-\w])(cursor|height|padding(?:-[a-z]+)?)\s*:/g, why: "sets cursor, height or padding outside lib/ui" },
];

function lint(plugin) {
	const found = [];
	for (const file of own(plugin)) {
		const text = readFileSync(file, "utf8");
		for (const rule of RULES) {
			if (!file.endsWith(rule.ext)) continue;
			for (const m of text.matchAll(rule.re)) {
				const line = text.slice(0, m.index).split("\n").length;
				found.push(`${relative(root, file)}:${line}: \`${m[0]}\` ${rule.why}`);
			}
		}
	}
	return found;
}

const mode = process.argv[2];
if (mode === "sync") {
	for (const plugin of plugins.filter(usesUi)) {
		rmSync(join(plugin, "ui"), { recursive: true, force: true });
		cpSync(lib, join(plugin, "ui"), { recursive: true });
		console.log(`synced ${relative(root, plugin)}/ui`);
	}
} else if (mode === "check") {
	const problems = [];
	for (const plugin of plugins) {
		if (usesUi(plugin)) {
			for (const name of syncDrift(plugin)) problems.push(`${relative(root, plugin)}/ui/${name} differs from lib/ui; run node scripts/ui.mjs sync`);
		}
		problems.push(...lint(plugin));
	}
	for (const p of problems) console.error(p);
	process.exit(problems.length ? 1 : 0);
} else {
	console.error("usage: node scripts/ui.mjs sync | check");
	process.exit(2);
}
