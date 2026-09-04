import { readFile, readdir, rename, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(toolsDirectory, "..");
const mediaFolders = ["images", "highres", "videos"];
const accountId =
  process.env.BELL_R2_ACCOUNT_ID ?? "ab56c50c894120419489f9be591fc67d";
const bucket =
  process.env.BELL_R2_BUCKET ?? "bell-family-archive-media";
const apiRoot =
  `https://api.cloudflare.com/client/v4/accounts/${accountId}` +
  `/r2/buckets/${bucket}/objects`;
const concurrency = Number.parseInt(process.env.BELL_R2_WORKERS ?? "6", 10);
const wranglerClientId = "54d11594-84e4-41aa-b438-e81b8fa78ee7";

const mimeTypes = new Map([
  [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"],
  [".png", "image/png"],
  [".gif", "image/gif"],
  [".webp", "image/webp"],
  [".mp4", "video/mp4"],
  [".mov", "video/quicktime"],
  [".m4v", "video/x-m4v"],
  [".avi", "video/x-msvideo"],
  [".webm", "video/webm"],
]);

function encodeObjectKey(key) {
  return key.split("/").map(encodeURIComponent).join("/");
}

async function getToken() {
  if (process.env.CLOUDFLARE_API_TOKEN) {
    return process.env.CLOUDFLARE_API_TOKEN;
  }

  const appData = process.env.APPDATA;
  if (!appData) throw new Error("APPDATA is unavailable");

  const configPath = path.join(
    appData,
    "xdg.config",
    ".wrangler",
    "config",
    "default.toml",
  );
  let config = await readFile(configPath, "utf8");
  let token = config.match(/^oauth_token\s*=\s*"([^"]+)"/m)?.[1];
  const expiration = config.match(/^expiration_time\s*=\s*"([^"]+)"/m)?.[1];

  if (!token) {
    throw new Error("Cloudflare login was not found. Run: wrangler login");
  }

  if (expiration && new Date(expiration).getTime() > Date.now() + 60_000) {
    return token;
  }

  const refreshToken = config.match(/^refresh_token\s*=\s*"([^"]+)"/m)?.[1];
  if (!refreshToken) {
    throw new Error("Cloudflare login expired. Run: wrangler login");
  }

  const response = await fetch("https://dash.cloudflare.com/oauth2/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
      client_id: wranglerClientId,
    }),
    signal: AbortSignal.timeout(30_000),
  });
  const body = await response.json();
  if (!response.ok || !body.access_token) {
    throw new Error("Cloudflare login expired. Run: wrangler login");
  }

  token = body.access_token;
  const nextExpiration = new Date(
    Date.now() + Number(body.expires_in) * 1000,
  ).toISOString();
  const nextRefreshToken = body.refresh_token ?? refreshToken;
  const replacements = new Map([
    ["oauth_token", token],
    ["expiration_time", nextExpiration],
    ["refresh_token", nextRefreshToken],
  ]);

  for (const [name, value] of replacements) {
    const expression = new RegExp(`^${name}\\s*=.*$`, "m");
    const line = `${name} = ${JSON.stringify(value)}`;
    config = expression.test(config)
      ? config.replace(expression, line)
      : `${config.trimEnd()}\n${line}\n`;
  }

  const temporaryPath = `${configPath}.tmp-${process.pid}`;
  await writeFile(temporaryPath, config, "utf8");
  await rename(temporaryPath, configPath);
  return token;
}

async function collectFiles(current) {
  const absoluteDirectory = path.join(repoRoot, current);
  const entries = await readdir(absoluteDirectory, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const relativePath = path.posix.join(current.replaceAll("\\", "/"), entry.name);
    if (entry.isDirectory()) {
      files.push(...(await collectFiles(relativePath)));
    } else if (entry.isFile()) {
      const absolutePath = path.join(repoRoot, relativePath);
      const details = await stat(absolutePath);
      if (details.size > 300_000_000) {
        throw new Error(`R2 REST upload limit exceeded: ${relativePath}`);
      }
      files.push({ absolutePath, key: relativePath, size: details.size });
    }
  }

  return files;
}

async function listRemoteObjects(token) {
  const objects = new Map();
  let cursor;

  do {
    const url = new URL(apiRoot);
    url.searchParams.set("per_page", "1000");
    if (cursor) url.searchParams.set("cursor", cursor);

    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const body = await response.json();
    if (!response.ok || !body.success) {
      throw new Error(`Unable to list R2 objects: ${JSON.stringify(body.errors)}`);
    }

    for (const object of body.result ?? []) {
      objects.set(object.key, Number(object.size));
    }
    cursor = body.result_info?.cursor || undefined;
  } while (cursor);

  return objects;
}

async function uploadFile(file, token) {
  const bytes = await readFile(file.absolutePath);
  const extension = path.extname(file.absolutePath).toLowerCase();
  const contentType = mimeTypes.get(extension) ?? "application/octet-stream";
  const url = `${apiRoot}/${encodeObjectKey(file.key)}`;

  for (let attempt = 1; attempt <= 5; attempt += 1) {
    try {
      const response = await fetch(url, {
        method: "PUT",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": contentType,
        },
        body: bytes,
      });
      const body = await response.json();
      if (response.ok && body.success) return;
      if (response.status === 401 || response.status === 403) {
        throw new Error("Cloudflare login expired. Run: wrangler login");
      }
      throw new Error(
        `HTTP ${response.status}: ${JSON.stringify(body.errors ?? body)}`,
      );
    } catch (error) {
      if (attempt === 5 || /login expired/i.test(error.message)) throw error;
      await new Promise((resolve) => setTimeout(resolve, 1000 * 2 ** (attempt - 1)));
    }
  }
}

const token = await getToken();
const localFiles = (
  await Promise.all(mediaFolders.map((folder) => collectFiles(folder)))
).flat();
const localBytes = localFiles.reduce((sum, file) => sum + file.size, 0);
const remoteObjects = await listRemoteObjects(token);
const pendingFiles = localFiles.filter(
  (file) => remoteObjects.get(file.key) !== file.size,
);

console.log(
  `Local media: ${localFiles.length} files, ${(localBytes / 1024 ** 3).toFixed(2)} GiB`,
);
console.log(`Already verified by size: ${localFiles.length - pendingFiles.length}`);
console.log(`Uploading now: ${pendingFiles.length}`);

let nextIndex = 0;
let completed = 0;
let uploadedBytes = 0;
const failures = [];

async function worker() {
  while (true) {
    const index = nextIndex;
    nextIndex += 1;
    if (index >= pendingFiles.length) return;

    const file = pendingFiles[index];
    try {
      await uploadFile(file, token);
      completed += 1;
      uploadedBytes += file.size;
      if (completed % 25 === 0 || completed === pendingFiles.length) {
        console.log(
          `Progress: ${completed}/${pendingFiles.length}, ${(uploadedBytes / 1024 ** 2).toFixed(1)} MiB`,
        );
      }
    } catch (error) {
      failures.push({ key: file.key, error: error.message });
      console.error(`FAILED ${file.key}: ${error.message}`);
    }
  }
}

await Promise.all(Array.from({ length: concurrency }, () => worker()));

if (failures.length) {
  console.error(JSON.stringify({ failed: failures.length, failures }));
  process.exitCode = 1;
} else {
  console.log(`Cloudflare verification complete: ${localFiles.length} files.`);
}
