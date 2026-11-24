#!/usr/bin/env node
// App Store Connect steps for Siren, through the API key in .asc.local. Read-only except `testflight` and `release`.
//
//   asc.mjs check
//     Looks the app up by bundle ID and says whether the record exists. Exits 1 when it doesn't.
//   asc.mjs testflight <build> <what-to-test.txt>
//     Waits for the iOS build with this build number to finish processing, sets "What to Test" on it,
//     and makes sure the internal group "Inceptyon" exists with every build, so internal testers get each new build.
//   asc.mjs release <version> <build> <whats-new.txt>
//     Finds or creates the version, attaches the build, sets What's New, and submits it for review,
//     released automatically on approval. The first version only gets its build: it goes in from the version page,
//     with the in-app purchases added there, and the command exits 3.
import fs from "node:fs";
import os from "node:os";
import crypto from "node:crypto";
import path from "node:path";

const BUNDLE_ID = "com.inceptyon.siren";
const GROUP = "Inceptyon";
const PLATFORMS = ["IOS"];
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");

function fail(message) {
  console.error(`asc: ${message}`);
  process.exit(1);
}

// .asc.local holds the xcodebuild flags for the key; read the same three values from it.
const flags = fs.existsSync(path.join(root, ".asc.local")) ? fs.readFileSync(path.join(root, ".asc.local"), "utf8") : fail(".asc.local not found");
const flag = (name) => flags.match(new RegExp(`-${name}\\s+(\\S+)`))?.[1] ?? fail(`.asc.local has no -${name}`);
const keyPath = flag("authenticationKeyPath").replace(/^~/, os.homedir());
const key = fs.existsSync(keyPath) ? fs.readFileSync(keyPath, "utf8") : fail(`API key not found at ${keyPath}`);
const keyID = flag("authenticationKeyID");
const issuer = flag("authenticationKeyIssuerID");

function token() {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const head = b64({ alg: "ES256", kid: keyID, typ: "JWT" });
  const body = b64({ iss: issuer, iat: now, exp: now + 1100, aud: "appstoreconnect-v1" });
  const sig = crypto.sign("sha256", Buffer.from(`${head}.${body}`), { key, dsaEncoding: "ieee-p1363" }).toString("base64url");
  return `${head}.${body}.${sig}`;
}

async function api(method, route, data) {
  const r = await fetch(`https://api.appstoreconnect.apple.com/${route}`, {
    method,
    headers: { authorization: `Bearer ${token()}`, "content-type": "application/json" },
    body: data ? JSON.stringify({ data }) : undefined,
  });
  const text = await r.text();
  const json = text ? JSON.parse(text) : {};
  if (!r.ok) throw new Error(`${method} ${route}: ${r.status} ${json.errors?.map((e) => e.detail ?? e.title).join("; ")}`);
  return json;
}

const findApp = async () => (await api("GET", `v1/apps?filter[bundleId]=${BUNDLE_ID}`)).data[0];
const missing = `no App Store Connect app for ${BUNDLE_ID}. Create it first: Apps > + > New App, platform iOS, bundle ID ${BUNDLE_ID}.`;
const notes = (file) => fs.readFileSync(file, "utf8").trim().slice(0, 4000);

// Processing usually takes 5 to 30 minutes.
async function processed(app, build, platform) {
  for (let i = 0; i < 90; i++) {
    const b = (await api("GET", `v1/builds?filter[app]=${app.id}&filter[version]=${build}&filter[preReleaseVersion.platform]=${platform}&limit=1`)).data[0];
    const state = b?.attributes.processingState;
    if (state === "VALID") return b;
    if (state && state !== "PROCESSING") fail(`${platform} build ${build} is ${state}`);
    if (i % 5 === 0) console.log(`asc: ${platform} build ${build} ${b ? "is processing" : "hasn't appeared yet"}...`);
    await new Promise((r) => setTimeout(r, 20000));
  }
  fail(`${platform} build ${build} still not processed after 30 minutes; run this step again later`);
}

async function check() {
  const app = await findApp();
  if (!app) fail(missing);
  console.log(`asc: found "${app.attributes.name}" (${BUNDLE_ID}), app ${app.id}`);
}

async function testflight(build, file) {
  const app = (await findApp()) ?? fail(missing);
  const whatsNew = notes(file);
  for (const platform of PLATFORMS) {
    const b = await processed(app, build, platform);
    const loc = (await api("GET", `v1/builds/${b.id}/betaBuildLocalizations`)).data.find((l) => l.attributes.locale === "en-US");
    if (loc) await api("PATCH", `v1/betaBuildLocalizations/${loc.id}`, { type: "betaBuildLocalizations", id: loc.id, attributes: { whatsNew } });
    else await api("POST", "v1/betaBuildLocalizations", { type: "betaBuildLocalizations", attributes: { locale: "en-US", whatsNew },
      relationships: { build: { data: { type: "builds", id: b.id } } } });
    console.log(`asc: What to Test set on ${platform} build ${build}`);
  }

  let group = (await api("GET", `v1/betaGroups?filter[app]=${app.id}&filter[name]=${GROUP}`)).data[0];
  group ??= (await api("POST", "v1/betaGroups", { type: "betaGroups", attributes: { name: GROUP, isInternalGroup: true, hasAccessToAllBuilds: true },
    relationships: { app: { data: { type: "apps", id: app.id } } } })).data;
  const testers = (await api("GET", `v1/betaGroups/${group.id}/betaTesters?limit=100`)).data;
  console.log(`asc: internal group "${GROUP}" has ${testers.length} tester${testers.length === 1 ? "" : "s"}, and gets every build`);
  if (!testers.length) console.log("asc: add App Store Connect users to it in TestFlight to get the build on their devices");
}

async function release(version, build, file) {
  const app = (await findApp()) ?? fail(missing);
  const whatsNew = notes(file);
  let first = false;
  for (const platform of PLATFORMS) {
    const b = await processed(app, build, platform);
    const versions = (await api("GET", `v1/apps/${app.id}/appStoreVersions?filter[platform]=${platform}&limit=50`)).data;
    let v = versions.find((x) => x.attributes.versionString === version);
    v ??= (await api("POST", "v1/appStoreVersions", { type: "appStoreVersions", attributes: { platform, versionString: version, releaseType: "AFTER_APPROVAL" },
      relationships: { app: { data: { type: "apps", id: app.id } } } })).data;
    await api("PATCH", `v1/appStoreVersions/${v.id}/relationships/build`, { type: "builds", id: b.id });
    console.log(`asc: ${platform} ${version} uses build ${build}`);

    // The first version has no What's New, and its in-app purchases go with it from the version page.
    if (!versions.some((x) => x.id !== v.id)) {
      first = true;
      continue;
    }
    const loc = (await api("GET", `v1/appStoreVersions/${v.id}/appStoreVersionLocalizations`)).data.find((l) => l.attributes.locale === "en-US");
    await api("PATCH", `v1/appStoreVersionLocalizations/${loc.id}`, { type: "appStoreVersionLocalizations", id: loc.id, attributes: { whatsNew } });
    await api("PATCH", `v1/appStoreVersions/${v.id}`, { type: "appStoreVersions", id: v.id, attributes: { releaseType: "AFTER_APPROVAL" } });

    const open = (await api("GET", `v1/reviewSubmissions?filter[app]=${app.id}&filter[platform]=${platform}&filter[state]=READY_FOR_REVIEW`)).data[0];
    const sub = open ?? (await api("POST", "v1/reviewSubmissions", { type: "reviewSubmissions", attributes: { platform },
      relationships: { app: { data: { type: "apps", id: app.id } } } })).data;
    const items = (await api("GET", `v1/reviewSubmissions/${sub.id}/items?include=appStoreVersion`)).data;
    if (!items.some((i) => i.relationships?.appStoreVersion?.data?.id === v.id))
      await api("POST", "v1/reviewSubmissionItems", { type: "reviewSubmissionItems",
        relationships: { reviewSubmission: { data: { type: "reviewSubmissions", id: sub.id } }, appStoreVersion: { data: { type: "appStoreVersions", id: v.id } } } });
    await api("PATCH", `v1/reviewSubmissions/${sub.id}`, { type: "reviewSubmissions", id: sub.id, attributes: { submitted: true } });
    console.log(`asc: ${platform} ${version} (${build}) submitted for review; it releases on approval`);
  }
  if (first) {
    console.log(`asc: ${version} is the first version. Submit both platforms from App Store Connect, with the in-app purchases added on the version page.`);
    process.exit(3);
  }
}

const [cmd, ...args] = process.argv.slice(2);
if (cmd === "check" && args.length === 0) await check();
else if (cmd === "testflight" && args.length === 2) await testflight(...args);
else if (cmd === "release" && args.length === 3) await release(...args);
else fail("usage: asc.mjs check | testflight <build> <what-to-test.txt> | release <version> <build> <whats-new.txt>");
