#!/usr/bin/env python3
"""Usage: python3 tools/jsfx_clean.py FILE ..."""
import re, sys

KEEP = re.compile(r'^\s*//\s*(tags:|author:|by JGWizrad|Requires\b)', re.I)


def strip_code(src):
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '"' or c == "'":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == '\\' else 1
            out.append(src[i:j + 1]); i = j + 1
        elif src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
        elif src.startswith('/*', i):
            j = src.find('*/', i + 2)
            if j < 0: raise ValueError('unclosed /* comment')
            body = src[i:j + 2]
            out.append('\n' * body.count('\n') if '\n' in body else ' ')
            i = j + 2
        else:
            out.append(c); i += 1
    return ''.join(out)


def clean(text):
    lines = text.split('\n')
    k = next((x for x, l in enumerate(lines) if re.match(r'^@\w', l)), len(lines))
    head, inblock = [], False
    for l in lines[:k]:
        s = l.strip()
        if inblock:
            if '*/' in s: inblock = False
            continue
        if s.startswith('/*'):
            inblock = '*/' not in s[2:]
            continue
        if s.startswith('//') and not KEEP.match(l):
            continue
        head.append(l.rstrip())
    body_src = '\n'.join(lines[k:])
    orig_body = body_src.split('\n')
    body = strip_code(body_src).split('\n')
    assert len(body) == len(orig_body)
    keep = [b.rstrip() for b, o in zip(body, orig_body) if b.strip() or not o.strip()]
    res, blank = [], 0
    for l in head + keep:
        blank = blank + 1 if not l.strip() else 0
        if blank <= 1: res.append(l)
    return '\n'.join(res).rstrip('\n') + '\n'


LUA_KEEP = re.compile(r'^--\s*(@description|@author|@version|by JGWizrad)', re.I)


def _lua_long(src, i):
    m = re.match(r'\[(=*)\[', src[i:])
    if not m: return -1
    j = src.find(']' + m.group(1) + ']', i + len(m.group(0)))
    if j < 0: raise ValueError('unclosed long bracket')
    return j + len(m.group(1)) + 2


def strip_lua(text):
    src, out, i, n = text, [], 0, len(text)
    while i < n:
        c = src[i]
        if c == '"' or c == "'":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == '\\' else 1
            out.append(src[i:j + 1]); i = j + 1
        elif c == '[' and _lua_long(src, i) > 0:
            j = _lua_long(src, i); out.append(src[i:j]); i = j
        elif src.startswith('--', i):
            e = _lua_long(src, i + 2)
            if e > 0:
                body = src[i:e]
                out.append('\n' * body.count('\n') if '\n' in body else ' ')
                i = e
            else:
                j = src.find('\n', i); j = n if j < 0 else j
                at_bol = i == 0 or src[i - 1] == '\n'
                if at_bol and LUA_KEEP.match(src[i:j]): out.append(src[i:j])
                i = j
        else:
            out.append(c); i += 1
    return ''.join(out)


def clean_lua(text):
    body, orig = strip_lua(text).split('\n'), text.split('\n')
    assert len(body) == len(orig)
    keep = [b.rstrip() for b, o in zip(body, orig) if b.strip() or not o.strip()]
    res, blank = [], 0
    for l in keep:
        blank = blank + 1 if not l.strip() else 0
        if blank <= 1: res.append(l)
    return '\n'.join(res).strip('\n') + '\n'


def is_clean(path):
    t = open(path, encoding='utf-8', errors='surrogateescape').read()
    r = clean_lua(t) if path.endswith('.lua') else clean(t)
    return r.rstrip('\n') == t.rstrip('\n')


def clean_file(p):
    t = open(p, encoding='utf-8', errors='surrogateescape').read()
    r = clean_lua(t) if p.endswith('.lua') else clean(t)
    open(p, 'w', encoding='utf-8', errors='surrogateescape').write(r)


if __name__ == '__main__':
    for p in sys.argv[1:]:
        clean_file(p)
