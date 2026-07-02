#!/usr/bin/env node
// Generate a scrypt password hash for APP_USERS.
// Usage:  node scripts/hash-password.mjs 'the-password'
// Output: scrypt:<saltHex>:<hashHex>   (paste as the "password" value in APP_USERS)
import { scryptSync, randomBytes } from "crypto";

const pw = process.argv[2];
if (!pw) {
  console.error("Usage: node scripts/hash-password.mjs '<password>'");
  process.exit(1);
}
const salt = randomBytes(16);
const hash = scryptSync(pw, salt, 32);
console.log(`scrypt:${salt.toString("hex")}:${hash.toString("hex")}`);
