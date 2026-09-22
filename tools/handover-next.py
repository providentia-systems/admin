#!/usr/bin/env python3
"""Complete the repository-to-HTTP search path identified by the regression."""
from pathlib import Path
p = Path('lib/features/catalog/catalog_maintenance_repository.dart')
s = p.read_text()
a = s.index('  Future<List<CatalogEntity>> list(')
b = s.index('  Future<CatalogEntity> save(', a)
part = s[a:b]
if "'q': query.trim()" not in part:
    needle = "'offset': '$offset'"
    assert needle in part
    part = part.replace(needle, needle + ", if (query.trim().isNotEmpty) 'q': query.trim()", 1)
s = s[:a] + part + s[b:]
p.write_text(s)
print('Catalog search is now forwarded with offset and the existing product filter.')
