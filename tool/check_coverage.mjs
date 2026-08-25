#!/usr/bin/env node

import { readFileSync, readdirSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const policy = JSON.parse(
  readFileSync(join(root, '.coverage-policy.json'), 'utf8'),
);
const reportPath = join(root, 'coverage', 'lcov.info');
const report = readFileSync(reportPath, 'utf8');

function dartSources(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return dartSources(path);
    if (!entry.isFile() || !entry.name.endsWith('.dart')) return [];
    return [relative(root, path).split(sep).join('/')];
  });
}

const records = report
  .split('end_of_record')
  .map((record) => {
    const source = record.match(/^SF:(.+)$/m)?.[1]?.replaceAll('\\', '/');
    const found = Number(record.match(/^LF:(\d+)$/m)?.[1] ?? 0);
    const hit = Number(record.match(/^LH:(\d+)$/m)?.[1] ?? 0);
    return { source, found, hit };
  })
  .filter(({ source }) => source != null);

const sources = dartSources(join(root, 'lib')).sort();
const missing = sources.filter(
  (source) => !records.some((record) => record.source.endsWith(source)),
);
if (missing.length > 0) {
  throw new Error(
    `Coverage is missing handwritten production libraries:\n${missing.join('\n')}`,
  );
}

const scoped = records.filter(({ source }) =>
  sources.some((candidate) => source.endsWith(candidate)),
);
const found = scoped.reduce((total, record) => total + record.found, 0);
const hit = scoped.reduce((total, record) => total + record.hit, 0);
if (found === 0) throw new Error('Coverage report contains no executable lines.');

const actualBasisPoints = Math.floor((hit * 10000) / found);
const minimumBasisPoints = policy.minimumLineCoveragePercent * 100;
const actualPercent = (actualBasisPoints / 100).toFixed(2);
console.log(
  `Handwritten production coverage: ${actualPercent}% (${hit}/${found}); ` +
    `minimum ${policy.minimumLineCoveragePercent}%, target ${policy.targetLineCoveragePercent}%.`,
);
if (actualBasisPoints < minimumBasisPoints) {
  throw new Error('Handwritten production coverage fell below the ratchet.');
}
