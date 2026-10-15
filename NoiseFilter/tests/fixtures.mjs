import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import vm from 'node:vm';

const path = process.argv[2];
const original = await import(pathToFileURL(`${path}.original.mjs`));
const embedded = vm.runInNewContext(JSON.parse((await readFile(path, 'utf8')).match(/= (.*);\n$/)[1]));
const plain = value => JSON.parse(JSON.stringify(value));
const decode = value => Array.isArray(value) ? value.map(decode) : value?.utf16 ? String.fromCharCode(...value.utf16) : value;
const cases = [];
function check(name, args) {
  let expected;
  try { expected = original[name](...decode(args)); } catch { expected = null; }
  let actual;
  try { actual = embedded[name](...decode(args)); } catch { actual = null; }
  assert.deepEqual(plain(actual), plain(expected));
  cases.push({ name, args, expected });
  return expected;
}
const video = { title: 'x'.repeat(230), channel: 'c', description: 'd'.repeat(1700), seconds: 3725, live: false };
const guidance = { utf16: [...Array(999).fill(120), 0xd83d, 0xde00] };
for (const text of ['', '  Hide anime.\n', guidance]) check('effectiveGuidance', [text]);
const requests = [check('decisionRequest', [video, 'QUJD', '', '']), check('decisionRequest', [video, 'QUJD', 't'.repeat(7000), guidance])];
const answers = requests[1].questions.map(q => ({ name: q.name, type: 'choice', probabilities: [{ value: q.choices[0].value, probability: 0.7 }, { value: 'uncertain', probability: 0.3 }] }));
const verdict = check('parseDecision', [{ answers }, requests[1].questions]);
check('needsTranscript', [verdict]);
for (const mutate of [a => a.slice(1), a => [a[0], ...a], a => a.map((v, i) => i ? v : { ...v, type: 'refusal' }), a => a.map((v, i) => i ? v : { ...v, probabilities: [{ value: 'invented', probability: 1 }] }), a => a.map((v, i) => i ? v : { ...v, probabilities: [{ value: 'no_signal', probability: 2 }] })]) check('parseDecision', [{ answers: mutate(answers) }, requests[1].questions]);
const text = original.effectiveGuidance(decode(guidance));
await writeFile(process.argv[3], JSON.stringify({ cases, categories: original.CATEGORIES, defaults: original.DEFAULT_SETTINGS, guidance, hash: createHash('sha256').update(text).digest('hex').slice(0, 16) }));
console.log(`${cases.length} original-module / bundled-module parity cases passed`);
