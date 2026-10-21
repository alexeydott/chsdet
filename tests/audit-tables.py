"""Audit checked-in literal state tables; not a Delphi execution substitute."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent

def arrays(path):
    text = re.sub(r"//[^\n]*", "", path.read_text())
    result = {}
    for name, bounds, kind, body in re.findall(
            r"(\w+)\s*:\s*array\s*\[([^]]+)\]\s*of\s*(\w+)\s*=\s*\((.*?)\);", text, re.I | re.S):
        body = re.sub(r"(?:byte|integer)\(eStart\)", "0", body, flags=re.I)
        body = re.sub(r"(?:byte|integer)\(eError\)", "1", body, flags=re.I)
        body = re.sub(r"(?:byte|integer)\(eItsMe\)", "2", body, flags=re.I)
        values = [int(x.strip()) for x in body.split(',') if x.strip()]
        count = 256 if bounds.lower() == 'ansichar' else int(bounds.split('..')[1]) + 1
        assert len(values) == count, (path.name, name, count, len(values))
        result[name.lower()] = (values, kind.lower())
    return text, result

def audit():
    print('model | factor | state bytes | reachable states | max reachable index')
    for path in sorted(ROOT.glob('*LangModel.inc')):
        text, tables = arrays(path)
        fields = dict(re.findall(r"(classTable|stateTable|charLenTable)\s*:\s*@(\w+)", text, re.I))
        factor = int(re.search(r'classFactor\s*:\s*(\d+)', text, re.I)[1])
        cls, _ = tables[fields['classTable'].lower()]
        st, _ = tables[fields['stateTable'].lower()]
        lens, kind = tables[fields['charLenTable'].lower()]
        assert len(cls) == 256 and max(cls) < factor
        span = len(lens) * (4 if kind == 'pruint32' else 1)
        assert max(cls) < span, (path.name, 'char length byte span')
        reachable, pending, max_index = {0}, [0], 0
        while pending:
            state = pending.pop()
            for c in cls:
                index = state * factor + c
                assert index < len(st), (path.name, state, c, index)
                max_index = max(max_index, index)
                nxt = st[index]
                if nxt not in reachable:
                    reachable.add(nxt)
                    pending.append(nxt)
        print(f'{path.stem} | {factor} | {len(st)} | {sorted(reachable)} | {max_index}')
        if kind != 'byte':
            print(f'  NOTE: charLenTable is {kind}; accessed as bytes; declared elements={len(lens)}, class max={max(cls)}')
        assert max_index < 2**32
    for path in sorted(ROOT.glob('*Freq.pas')):
        text = re.sub(r'//[^\n]*', '', path.read_text())
        text = re.sub(r'\(\*.*?\*\)|\{.*?\}', '', text, flags=re.S)
        size_text = re.search(r'\w+_TABLE_SIZE\s*=\s*([0-9+ -]+);', text)[1]
        size = sum(int(x) for x in re.findall(r'[+-]?\s*\d+', size_text.replace(' ', '')))
        body = re.search(r'array.*?of PRInt16\s*=\s*\((.*?)\);', text, re.S | re.I)[1]
        values = [int(x.strip()) for x in body.split(',') if x.strip()]
        assert len(values) == size and all(-32768 <= x <= 32767 for x in values)
        print(f'{path.name}: {size} Int16 entries; declared size matches')

if __name__ == '__main__':
    audit()
