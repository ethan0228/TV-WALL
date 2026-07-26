import { pbkdf2Sync, randomBytes } from "node:crypto";

let password = "";
process.stdin.setEncoding("utf8");
for await (const chunk of process.stdin) password += chunk;
password = password.replace(/\r?\n$/, "");

if (password.length < 10) {
  console.error("管理員密碼至少需要 10 個字元。");
  process.exit(2);
}

const iterations = 310_000;
const salt = randomBytes(16);
const hash = pbkdf2Sync(password, salt, iterations, 32, "sha256");
const base64url = (value) =>
  value
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");

process.stdout.write(
  `pbkdf2_sha256$${iterations}$${base64url(salt)}$${base64url(hash)}`,
);
