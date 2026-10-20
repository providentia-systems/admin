#!/usr/bin/env node

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const action = 'actions/download-artifact';

export function verifyArtifactActionPins(workflows) {
  if (workflows.length === 0) {
    throw new Error('Provide the workflow files whose artifact downloads must be pinned.');
  }

  let expectedPin;
  for (const { path, content } of workflows) {
    let downloads = 0;
    for (const [index, line] of content.split(/\r?\n/).entries()) {
      const use = /^\s*(?:-\s+)?uses:\s*(.*)$/.exec(line);
      if (!use) continue;
      if (!/^['"]?actions\/download-artifact(?:@|['"\s]|$)/.test(use[1])) continue;

      // Handle ordinary YAML scalars, including quoted refs and version comments.
      const scalar = /^(?:"([^"]*)"|'([^']*)'|([^\s#]+))\s*(?:#.*)?$/.exec(use[1]);
      const reference = scalar?.slice(1).find((value) => value !== undefined);

      const location = `${path}:${index + 1}`;
      const match = /^actions\/download-artifact@([0-9a-f]{40})$/.exec(reference ?? '');
      if (!match) {
        throw new Error(`${location}: ${action} must use a full immutable commit SHA.`);
      }
      if (expectedPin !== undefined && match[1] !== expectedPin) {
        throw new Error(`${location}: ${action} commit must match every download in the checked workflows.`);
      }
      expectedPin = match[1];
      downloads += 1;
    }
    if (downloads === 0) {
      throw new Error(`${path}: missing a pinned ${action} step.`);
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    verifyArtifactActionPins(process.argv.slice(2).map((path) => ({
      path,
      content: readFileSync(path, 'utf8'),
    })));
    console.log('Artifact downloads use a consistent immutable commit pin.');
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
