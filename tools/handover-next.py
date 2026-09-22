#!/usr/bin/env python3
"""Apply the reviewed analyzer corrections without changing test gates."""
from pathlib import Path
p = Path('lib/features/catalog/catalog_page.dart')
s = p.read_text()
s = s.replace(')\n      return;', ') {\n      return;\n    }')
s = s.replace('if (!_isAuthorized(epoch)) return;', 'if (!mounted || !_isAuthorized(epoch)) return;')
p.write_text(s)
print('Explicit mounted guards and braced early returns applied.')
