import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import vm from 'node:vm';

const path = process.argv[2];
const original = await import(pathToFileURL(`${path}.original.mjs`));
const embedded = vm.runInNewContext(JSON.parse((await readFile(path, 'utf8')).match(/= (.*);\n$/)[1]), { crypto: { randomUUID } });
const plain = value => {
  const result = JSON.parse(JSON.stringify(value));
  if (result?.assets) {
    const [reference] = Object.keys(result.assets);
    assert.match(reference, /^[0-9a-f-]{36}$/);
    assert.ok(result.state.includes(reference));
    result.state = result.state.replaceAll(reference, 'fixture-thumbnail');
    result.assets = { 'fixture-thumbnail': result.assets[reference] };
  }
  return result;
};
const decode = value => Array.isArray(value) ? value.map(decode) : value?.utf16 ? String.fromCharCode(...value.utf16) : value;
const cases = [];
function check(name, args) {
  let expected;
  try { expected = original[name](...decode(args)); } catch { expected = null; }
  let actual;
  try { actual = embedded[name](...decode(args)); } catch { actual = null; }
  assert.deepEqual(plain(actual), plain(expected));
  cases.push({ name, args, expected: plain(expected) });
  return plain(expected);
}
const video = { title: 'x'.repeat(230), channel: 'c', description: 'd'.repeat(1700), seconds: 3725, live: false };
const guidance = { utf16: [...Array(999).fill(120), 0xd83d, 0xde00] };
for (const text of ['', '  Hide anime.\n', guidance]) check('effectiveGuidance', [text]);
const requests = [check('decisionRequest', [video, 'QUJD', '', '']), check('decisionRequest', [video, 'QUJD', 't'.repeat(7000), guidance])];
assert.equal(original.SYSTEM_ONE_URL, 'https://api.typesafe.ai/v1/systemone');
assert.equal(requests[0].model, 'jev-1.14.0');
const answers = Object.fromEntries(Object.entries(requests[1].questions).map(([name, q]) => [name, { type: 'choice', probabilities: { [Object.keys(q.criteria)[0]]: 0.7, uncertain: 0.3 } }]));
const verdict = check('parseDecision', [{ answers }, requests[1].questions]);
check('needsTranscript', [verdict]);
const [first] = Object.keys(answers);
for (const mutate of [a => Object.fromEntries(Object.entries(a).slice(1)), a => ({ ...a, invented: a[first] }), a => ({ ...a, [first]: { type: 'refusal' } }), a => ({ ...a, [first]: { type: 'choice', probabilities: { invented: 1 } } }), a => ({ ...a, [first]: { type: 'choice', probabilities: { no_signal: 2 } } })]) check('parseDecision', [{ answers: mutate(answers) }, requests[1].questions]);
check('withDefaults', [{ strictness: 'strict', categories: { noise: false } }]);
check('overrides', [original.DEFAULT_SETTINGS]);
const text = original.effectiveGuidance(decode(guidance));
const identity = `${original.SYSTEM_ONE_URL}\n${original.DEFAULT_SETTINGS.model}\n${JSON.stringify(original.VIDEO_POLICY)}\n${text}`;
await writeFile(process.argv[3], JSON.stringify({ cases, categories: original.CATEGORIES, defaults: original.DEFAULT_SETTINGS, guidance, hash: createHash('sha256').update(identity).digest('hex').slice(0, 16) }));
console.log(`${cases.length} original-module / bundled-module parity cases passed`);
