#!/usr/bin/env node
// Loopback receiver for the Automations event inbox.
//
//   TERN_AUTOMATIONS_RECEIVER_TOKEN=<secret> node receiver.mjs [--port N]
//
// Accepts POST /events with `Authorization: Bearer <token>` and a normalized event:
//   { id, source: github|webhook|slack|linear, event, at?, attributes?, payload? }
// and writes it to the inbox the Automations plugin reads. It listens on 127.0.0.1 only.
//
// This is a bridge ingress, not a provider integration: it does not subscribe to GitHub,
// Slack or Linear and verifies no provider signature. A separately trusted bridge that
// already authenticated the provider delivery posts the normalized event here.
// The token comes from the environment, never argv, and is never logged.

import { createHash, timingSafeEqual, randomBytes } from "node:crypto";
import { createServer } from "node:http";
import { realpathSync } from "node:fs";
import { mkdir, open, readdir, rm, stat, link, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const SOURCES = new Set(["github", "webhook", "slack", "linear"]);
const MAX_BODY = 64 * 1024;
const MAX_INBOX = 1000;
const SEEN_TTL_MS = 7 * 24 * 3600 * 1000;
const MIN_TOKEN = 16;

export function defaultStateDir(env = process.env) {
	const override = env.TERN_AUTOMATIONS_HOME;
	return override ? join(override, "state") : join(homedir(), ".local", "state", "tern-automations");
}

const isObject = (v) => typeof v === "object" && v !== null && !Array.isArray(v);

// Returns the normalized event, or a string naming what is wrong (never echoing the input).
export function validateEvent(doc) {
	if (!isObject(doc)) return "body must be a JSON object";
	for (const key of Object.keys(doc)) {
		if (!["id", "source", "event", "at", "attributes", "payload"].includes(key)) return `unknown field ${key}`;
	}
	if (typeof doc.id !== "string" || !/^[A-Za-z0-9._:-]{1,128}$/.test(doc.id)) return "invalid id";
	if (typeof doc.source !== "string" || !SOURCES.has(doc.source)) return "invalid source";
	if (typeof doc.event !== "string" || !/^[A-Za-z0-9._:/-]{1,128}$/.test(doc.event)) return "invalid event";
	if (doc.at !== undefined && !(Number.isInteger(doc.at) && doc.at >= 0)) return "invalid at";
	if (doc.attributes !== undefined) {
		if (!isObject(doc.attributes)) return "invalid attributes";
		const entries = Object.entries(doc.attributes);
		if (entries.length > 32) return "too many attributes";
		for (const [k, v] of entries) {
			if (!/^[A-Za-z0-9_.-]{1,64}$/.test(k) || typeof v !== "string" || Buffer.byteLength(v) > 256) return "invalid attributes";
		}
	}
	return doc;
}

const digest = (text) => createHash("sha256").update(text).digest();

export function createReceiver({ token, stateDir = defaultStateDir(), now = () => Date.now() }) {
	if (typeof token !== "string" || token.length < MIN_TOKEN) {
		throw new Error(`TERN_AUTOMATIONS_RECEIVER_TOKEN must be set to a secret of at least ${MIN_TOKEN} characters`);
	}
	const want = digest(token);
	const inbox = join(stateDir, "events", "inbox");
	const seen = join(stateDir, "events", "seen");

	const authorized = (header) => {
		const m = typeof header === "string" ? /^Bearer (.+)$/.exec(header) : null;
		return m !== null && timingSafeEqual(digest(m[1]), want);
	};

	const reply = (res, status, body) => {
		const text = JSON.stringify(body);
		res.writeHead(status, { "content-type": "application/json", "content-length": Buffer.byteLength(text), connection: "close" });
		res.end(text);
	};

	const readBody = (req) =>
		new Promise((resolve, reject) => {
			const chunks = [];
			let size = 0;
			req.on("data", (chunk) => {
				size += chunk.length;
				if (size > MAX_BODY) {
					reject(Object.assign(new Error("too large"), { code: "TOO_LARGE" }));
					req.destroy();
					return;
				}
				chunks.push(chunk);
			});
			req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
			req.on("error", reject);
		});

	async function acceptOne(event) {
		const name = `${event.source}-${createHash("sha256").update(`${event.source}:${event.id}`).digest("hex").slice(0, 32)}.json`;
		await mkdir(inbox, { recursive: true, mode: 0o700 });
		await mkdir(seen, { recursive: true, mode: 0o700 });
		if ((await readdir(inbox)).length >= MAX_INBOX) return "full";
		let marker;
		try {
			marker = await open(join(seen, name), "wx", 0o600);
		} catch (err) {
			if (err.code === "EEXIST") return "duplicate";
			throw err;
		}
		await marker.close();
		const tmp = join(inbox, `.tmp-${randomBytes(8).toString("hex")}`);
		try {
			const file = await open(tmp, "wx", 0o600);
			await file.writeFile(JSON.stringify({ ...event, received_at: Math.floor(now() / 1000) }));
			await file.close();
			await link(tmp, join(inbox, name));
		} catch (err) {
			await rm(join(seen, name), { force: true });
			throw err;
		} finally {
			await unlink(tmp).catch(() => {});
		}
		return "accepted";
	}

	let queue = Promise.resolve();
	const accept = (event) => {
		const run = queue.then(() => acceptOne(event));
		queue = run.catch(() => {});
		return run;
	};

	async function pruneSeen() {
		try {
			for (const name of await readdir(seen)) {
				const info = await stat(join(seen, name));
				if (now() - info.mtimeMs > SEEN_TTL_MS) await rm(join(seen, name), { force: true });
			}
		} catch {
		}
	}

	const server = createServer(async (req, res) => {
		try {
			if (!req.url || new URL(req.url, "http://localhost").pathname !== "/events") return reply(res, 404, { error: "not found" });
			if (req.method !== "POST") return reply(res, 405, { error: "use POST" });
			if (!authorized(req.headers.authorization)) return reply(res, 401, { error: "unauthorized" });
			if (!/^application\/json\b/i.test(req.headers["content-type"] ?? "")) return reply(res, 415, { error: "send application/json" });
			if (Number(req.headers["content-length"] ?? 0) > MAX_BODY) return reply(res, 413, { error: "body too large" });
			let doc;
			try {
				doc = JSON.parse(await readBody(req));
			} catch (err) {
				return err.code === "TOO_LARGE" ? reply(res, 413, { error: "body too large" }) : reply(res, 400, { error: "body is not JSON" });
			}
			const event = validateEvent(doc);
			if (typeof event === "string") return reply(res, 400, { error: event });
			const outcome = await accept(event);
			if (outcome === "full") return reply(res, 503, { error: "inbox is full" });
			return reply(res, outcome === "duplicate" ? 200 : 202, { status: outcome, id: event.id });
		} catch {
			return reply(res, 500, { error: "could not store the event" });
		}
	});

	return {
		server,
		inbox,
		listen: (port = 0) =>
			new Promise((resolve, reject) => {
				server.once("error", reject);
				server.listen(port, "127.0.0.1", () => {
					pruneSeen();
					const timer = setInterval(pruneSeen, 3600 * 1000);
					timer.unref();
					server.once("close", () => clearInterval(timer));
					resolve(server.address());
				});
			}),
		close: () => new Promise((resolve) => server.close(() => resolve())),
	};
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
	const flag = process.argv.indexOf("--port");
	const port = flag > 0 ? Number(process.argv[flag + 1]) : Number(process.env.TERN_AUTOMATIONS_RECEIVER_PORT ?? 47821);
	try {
		const receiver = createReceiver({ token: process.env.TERN_AUTOMATIONS_RECEIVER_TOKEN });
		const address = await receiver.listen(port);
		console.log(`automations receiver listening on 127.0.0.1:${address.port}`);
	} catch (err) {
		console.error(err.message);
		process.exit(1);
	}
}
