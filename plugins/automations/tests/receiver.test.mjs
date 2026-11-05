import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline";
import { after, before, test } from "node:test";
import { fileURLToPath } from "node:url";
import { createReceiver } from "../receiver.mjs";

const TOKEN = "example-token-for-tests-only";
let dir;
let receiver;
let base;

before(async () => {
	dir = mkdtempSync(join(tmpdir(), "automations-receiver-"));
	receiver = createReceiver({ token: TOKEN, stateDir: dir, now: () => 1_800_000_000_000 });
	const address = await receiver.listen(0);
	assert.equal(address.address, "127.0.0.1");
	base = `http://127.0.0.1:${address.port}/events`;
});

after(async () => {
	await receiver.close();
	rmSync(dir, { recursive: true, force: true });
});

const post = (body, headers = {}) =>
	fetch(base, {
		method: "POST",
		headers: { "content-type": "application/json", authorization: `Bearer ${TOKEN}`, ...headers },
		body: typeof body === "string" ? body : JSON.stringify(body),
	});

const event = (id) => ({ id, source: "github", event: "pull_request", attributes: { repo: "example-org/example-repo" }, payload: { n: 1 } });

test("a missing or wrong bearer is refused before anything touches disk", async () => {
	assert.equal((await post(event("a"), { authorization: "" })).status, 401);
	assert.equal((await post(event("a"), { authorization: "Bearer wrong" })).status, 401);
	assert.equal((await post(event("a"), { authorization: `Basic ${TOKEN}` })).status, 401);
	assert.equal(existsSync(join(dir, "events")), false);
});

test("an invalid payload is refused and writes nothing", async () => {
	assert.equal((await post({ ...event("b"), source: "email" })).status, 400);
	assert.equal((await post({ ...event("b"), extra: 1 })).status, 400);
	assert.equal((await post("not json")).status, 400);
	assert.equal((await post(event("bad id"))).status, 400);
	assert.equal(existsSync(receiver.inbox) ? readdirSync(receiver.inbox).length : 0, 0);
});

test("an oversized body is refused", async () => {
	const big = { ...event("c"), payload: "x".repeat(70 * 1024) };
	assert.equal((await post(big)).status, 413);
});

test("a valid event lands in the inbox, owner-only, stamped with its arrival", async () => {
	const res = await post(event("d1"));
	assert.equal(res.status, 202);
	const [name] = readdirSync(receiver.inbox).filter((n) => !n.startsWith("."));
	assert.match(name, /^github-[0-9a-f]{32}\.json$/);
	const stored = JSON.parse(readFileSync(join(receiver.inbox, name), "utf8"));
	assert.equal(stored.id, "d1");
	assert.equal(stored.received_at, 1_800_000_000);
	assert.equal(statSync(join(receiver.inbox, name)).mode & 0o777, 0o600);
	assert.equal(readdirSync(receiver.inbox).some((n) => n.startsWith(".tmp-")), false);
});

test("a repeated delivery id is a duplicate, even after the inbox file was consumed", async () => {
	const again = await post(event("d1"));
	assert.equal(again.status, 200);
	assert.equal((await again.json()).status, "duplicate");
	for (const name of readdirSync(receiver.inbox)) rmSync(join(receiver.inbox, name));
	assert.equal((await (await post(event("d1"))).json()).status, "duplicate");
	assert.equal(readdirSync(receiver.inbox).length, 0);
});

test("only POST /events exists", async () => {
	assert.equal((await fetch(base)).status, 405);
	assert.equal((await fetch(base.replace("/events", "/other"))).status, 404);
});

test("a short or missing token refuses to start", () => {
	assert.throws(() => createReceiver({ token: undefined, stateDir: dir }));
	assert.throws(() => createReceiver({ token: "short", stateDir: dir }));
});

test("launch.sh feeds the prompt file on stdin, keeps arguments intact and saves the pane's output", () => {
	const script = join(dirname(fileURLToPath(import.meta.url)), "..", "launch.sh");
	const prompt = join(dir, "prompt.md");
	const output = join(dir, "output.txt");
	const fakeTern = join(dir, "fake-tern");
	writeFileSync(prompt, "line one\n$(not run) `not run`\n");
	writeFileSync(fakeTern, '#!/bin/sh\necho "$*"\n', { mode: 0o755 });
	const env = { ...process.env, TERN_EXE: fakeTern, TERN_PANE: "7" };
	const out = spawnSync("sh", [script, output, prompt, "sh", "-c", 'cat; printf "%s|" "$@"; exit 3', "arg0", "a b", "$HOME"], { encoding: "utf8", env });
	assert.equal(out.status, 3);
	assert.equal(out.stdout, "line one\n$(not run) `not run`\na b|$HOME|");
	assert.equal(readFileSync(output, "utf8"), "capture 7 --scrollback\n");
	const bare = spawnSync("sh", [script, output, "-", "sh", "-c", "echo hi; cat"], { encoding: "utf8", env, input: "" });
	assert.equal(bare.status, 0);
	assert.equal(bare.stdout, "hi\n");
});

test("the receiver CLI accepts events through a symlinked plugin directory", { timeout: 5000 }, async (t) => {
	const plugin = dirname(dirname(fileURLToPath(import.meta.url)));
	const linked = join(dir, "linked-plugin");
	symlinkSync(plugin, linked, "dir");
	const home = join(dir, "cli-data");
	const child = spawn(process.execPath, [join(linked, "receiver.mjs"), "--port", "0"], {
		env: { ...process.env, TERN_AUTOMATIONS_HOME: home, TERN_AUTOMATIONS_RECEIVER_TOKEN: TOKEN },
		stdio: ["ignore", "pipe", "ignore"],
	});
	t.after(async () => {
		if (child.exitCode === null && child.signalCode === null) {
			const exited = once(child, "exit");
			child.kill();
			await exited;
		}
	});
	const lines = createInterface({ input: child.stdout });
	t.after(() => lines.close());
	const line = await Promise.race([
		once(lines, "line").then(([text]) => text),
		once(child, "exit").then(([code]) => { throw new Error(`receiver exited ${code} before listening`); }),
	]);
	const address = /127\.0\.0\.1:\d+/.exec(line)?.[0];
	const response = await fetch(`http://${address}/events`, {
		method: "POST",
		headers: { "content-type": "application/json", authorization: `Bearer ${TOKEN}` },
		body: JSON.stringify({ id: "cli-delivery", source: "webhook", event: "created" }),
	});
	assert.equal(response.status, 202);
	const inbox = join(home, "state", "events", "inbox");
	const stored = readdirSync(inbox).filter((name) => !name.startsWith("."));
	assert.equal(JSON.parse(readFileSync(join(inbox, stored[0]), "utf8")).id, "cli-delivery");
});

test("concurrent deliveries cannot overfill the inbox", async () => {
	const crowded = mkdtempSync(join(tmpdir(), "automations-receiver-full-"));
	const full = createReceiver({ token: TOKEN, stateDir: crowded, now: () => 1_800_000_000_000 });
	const address = await full.listen(0);
	try {
		mkdirSync(full.inbox, { recursive: true });
		for (let i = 0; i < 999; i += 1) writeFileSync(join(full.inbox, `filler-${i}.json`), "{}");
		const url = `http://127.0.0.1:${address.port}/events`;
		const send = (id) =>
			fetch(url, {
				method: "POST",
				headers: { "content-type": "application/json", authorization: `Bearer ${TOKEN}` },
				body: JSON.stringify(event(id)),
			});
		const statuses = (await Promise.all([send("c1"), send("c2")])).map((res) => res.status).sort();
		assert.deepEqual(statuses, [202, 503]);
		assert.equal(readdirSync(full.inbox).length, 1000);
	} finally {
		await full.close();
		rmSync(crowded, { recursive: true, force: true });
	}
});
