import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const css = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "styles.css"), "utf8");
const SPACING = new Set([0, 4, 8, 16, 24, 32, 40]);

function pixelValues(property) {
	const found = [];
	for (const m of css.matchAll(new RegExp(`(?<![-\\w])${property}:\\s*([^;}]+)`, "g"))) {
		for (const v of m[1].matchAll(/(?<![-\d])(\d+)px/g)) found.push(Number(v[1]));
	}
	return found;
}

test("padding, margin and gap sit on the 4/8/16/24/32/40 scale", () => {
	for (const property of ["padding", "padding-top", "padding-bottom", "margin", "margin-top", "gap"]) {
		for (const value of pixelValues(property)) assert.ok(SPACING.has(value), `${property}: ${value}px`);
	}
});

test("heights, widths and line heights are multiples of 4", () => {
	for (const property of ["height", "min-height", "max-height", "width", "min-width", "max-width", "line-height"]) {
		for (const value of pixelValues(property)) assert.equal(value % 4, 0, `${property}: ${value}px`);
	}
});

test("every screen shares the page rule", () => {
	assert.doesNotMatch(css, /editorPage|runPage/);
	assert.deepEqual([...css.matchAll(/(?<![-\w(])max-width:\s*(\d+)px/g)].map((m) => Number(m[1])), [1440]);
});

const view = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "view.luau"), "utf8");

function declarationsFor(role) {
	const out = [];
	for (const [, selector, body] of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
		if (selector.includes(`'${role}'`)) out.push(body);
	}
	return out.join(";");
}

test("a text leaf with a fixed height centers its line", () => {
	const roles = new Set();
	for (const [, list] of view.matchAll(/\btext\((?:[^()\n]|\([^()\n]*\))*?"(automations\.[\w.]+(?: automations\.[\w.]+)*)"\s*[,)]/g)) {
		for (const role of list.split(" ")) roles.add(role);
	}
	for (const role of roles) {
		const body = declarationsFor(role);
		const height = body.match(/(?<![-\w])height:\s*(\d+)px/);
		if (height) assert.match(body, new RegExp(`line-height:\\s*${height[1]}px`), `${role} sets height ${height[1]}px but not a matching line-height`);
	}
});
