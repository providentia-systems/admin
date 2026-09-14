"""Temporary integrity-checked source transfer. Removed after materialization."""
from pathlib import Path
import gzip
import hashlib
import json
import subprocess
root = Path(__file__).resolve().parent.parent
packed = b''.join((root / f'tool/step3-preflight.patch.gz.part{i}').read_bytes() for i in range(4))
patch = gzip.decompress(packed)
assert hashlib.sha256(patch).hexdigest() == '9f9e2946f89793b2bbb8a729b6cce7291ecce4f9a7cb449795155f403e2891ce'
subprocess.run(['git', 'apply', '--check', '-'], input=patch, cwd=root, check=True)
subprocess.run(['git', 'apply', '-'], input=patch, cwd=root, check=True)
archive = root / 'contracts/source/providentia-v1.json.gz'
contract = json.loads(gzip.decompress(archive.read_bytes()))
properties = contract['components']['schemas']['DataGovernanceRequest']['properties']
properties['downloadEligible'] = {'type': 'boolean', 'default': False, 'description': 'True only for a completed, unexpired export with an available artifact requested by the authenticated viewer. Rechecked before authenticated single-use token issuance and retrieval.'}
properties.setdefault('homeId', {'type': ['string', 'null'], 'format': 'uuid', 'description': 'Home scope for a home request; null for an account request.'})
raw = (json.dumps(contract, ensure_ascii=False, indent=2) + '\n').encode()
assert hashlib.sha256(raw).hexdigest() == 'f6591ae866efbcc9e661528c7f595da0d7093d959d64c66c09b0c5be1dcb7c58'
encoded = gzip.compress(raw, mtime=0)
archive.write_bytes(encoded)
materializer = root / 'tool/materialize-openapi-contract.sh'
materializer.write_text(materializer.read_text().replace('9550a7278a8231eb7b90ca338e8b157d2e63058dafbc1bc9b05c1e553d82af11', hashlib.sha256(encoded).hexdigest()))
(root / 'contracts/openapi/providentia-v1.json').write_bytes(raw)
print('Applied exact Step 3 catalog source and paired contract.')
