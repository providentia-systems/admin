from pathlib import Path
p=Path('lib/features/catalog/catalog_page.dart');s=p.read_text()
old='''        Row(
          children: <Widget>[
            SegmentedButton<_CatalogLane>('''
new='''        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SegmentedButton<_CatalogLane>('''
assert old in s;s=s.replace(old,new,1)
s=s.replace('            const Spacer(),\n','')
start=s.index('  Future<String?> _textDialog(');end=s.index('  void _clearPreview()',start)
part=s[start:end].replace('final controller = TextEditingController();',"var value = ''; // TextField owns its controller for the route lifetime.").replace('controller: controller,','onChanged: (text) => value = text,').replace('controller.text.trim()', 'value.trim()').replace('    controller.dispose();\n','')
s=s[:start]+part+s[end:];p.write_text(s)
