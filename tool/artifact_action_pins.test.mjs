import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { verifyArtifactActionPins } from './verify_artifact_action_pins.mjs';

const oldPin = '3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c';
const newPin = '9000827ccba6bdab643e8b6fd33ac0654aef8333';
const step = (pin) => `      - uses: actions/download-artifact@${pin}\n`;
const workflows = (quality, release = quality) => [
  { path: 'quality.yml', content: quality },
  { path: 'release-linux.yml', content: release },
];

test('current quality and release artifact downloads have consistent immutable pins', () => {
  verifyArtifactActionPins(['quality.yml', 'release-linux.yml'].map((name) => ({
    path: name,
    content: readFileSync(new URL(`../.github/workflows/${name}`, import.meta.url), 'utf8'),
  })));
});

test('a coordinated Dependabot update is accepted without changing the verifier', () => {
  for (const pin of [oldPin, newPin]) {
    verifyArtifactActionPins(workflows(step(pin), step(pin).repeat(2)));
  }
});

test('quoted refs and version comments remain valid', () => {
  verifyArtifactActionPins(workflows(
    `    uses: 'actions/download-artifact@${newPin}' # v8.0.2\n`,
    `    uses: "actions/download-artifact@${newPin}"\n`,
  ));
});

test('mutable, shortened and malformed refs are rejected', () => {
  for (const ref of ['v8', 'main', newPin.slice(0, 7), `${newPin}0`, 'g'.repeat(40), `${newPin} invalid`]) {
    assert.throws(() => verifyArtifactActionPins(workflows(step(ref))), /full immutable commit SHA/);
  }
  assert.throws(
    () => verifyArtifactActionPins(workflows('    uses: actions/download-artifact\n')),
    /full immutable commit SHA/,
  );
});

test('every artifact download must use the same commit, including a second release step', () => {
  assert.throws(
    () => verifyArtifactActionPins(workflows(step(newPin), step(newPin) + step(oldPin))),
    /release-linux.yml:2:.*commit must match/,
  );
});

test('a missing download in either workflow cannot be satisfied by a comment or another file', () => {
  for (const missing of ['', `    # uses: actions/download-artifact@${newPin}\n`]) {
    assert.throws(() => verifyArtifactActionPins(workflows(step(newPin), missing)), /release-linux.yml: missing/);
    assert.throws(() => verifyArtifactActionPins(workflows(missing, step(newPin))), /quality.yml: missing/);
  }
  assert.throws(() => verifyArtifactActionPins([]), /Provide the workflow files/);
});
