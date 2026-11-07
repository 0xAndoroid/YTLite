import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const revision = '6d3a427826757fd14402a27841e21aeef56281a2';
const digest = 'c07984593062497bb86d0be560cedc6ec45c6066f498eab67ac3f405f813092a';
const source = await readFile(new URL('./verdict.js', import.meta.url), 'utf8');
if (createHash('sha256').update(source).digest('hex') !== digest) throw new Error(`Contract differs from yt-noise-filter ${revision}`);
const names = [...source.matchAll(/^export (?:const|class|function) (\w+)/gm)].map(m => m[1]);
const script = `(() => { 'use strict';\n${source.replace(/^export /gm, '')}\nreturn {${names.join(',')}, categoryNames: Object.keys(CATEGORIES), judgedNames: Object.keys(JUDGED)}; })()`;
const output = process.argv[2];
const root = fileURLToPath(new URL('../', import.meta.url));
const head = execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
const dirty = execFileSync('git', ['-C', root, 'status', '--porcelain', '--', 'NoiseFilter'], { encoding: 'utf8' }).trim();
await mkdir(dirname(output), { recursive: true });
await writeFile(output, `#define NF_BUILD_REVISION ${JSON.stringify(head + (dirty ? '-modified' : ''))}\nstatic const char NFContractSource[] = ${JSON.stringify(script)};\n`);
await writeFile(`${output}.original.mjs`, source);
