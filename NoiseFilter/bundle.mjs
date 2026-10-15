import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

const revision = '8416a924642c866107c1734bedb75aaed993697a';
const digest = 'ebdb42863f1960b22942352e195c9ac3faf256759bb9ea9646108c58cef43c5b';
const source = await readFile(new URL('./verdict.js', import.meta.url), 'utf8');
if (createHash('sha256').update(source).digest('hex') !== digest) throw new Error(`Contract differs from yt-noise-filter ${revision}`);
const names = [...source.matchAll(/^export (?:const|class|function) (\w+)/gm)].map(m => m[1]);
const script = `(() => { 'use strict';\n${source.replace(/^export /gm, '')}\nreturn {${names.join(',')}, categoryNames: Object.keys(CATEGORIES), judgedNames: Object.keys(JUDGED)}; })()`;
const output = process.argv[2];
await mkdir(dirname(output), { recursive: true });
await writeFile(output, `static const char NFContractSource[] = ${JSON.stringify(script)};\n`);
await writeFile(`${output}.original.mjs`, source);
