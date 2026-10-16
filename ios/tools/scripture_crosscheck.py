"""Charter S cross-check against an independent second source: the ShabadOS 4.8.7 database.

Evidence for Charter S (docs/ios/testflight-test-plan.md §3) that does not come from our own
pipeline. Compares the pinned dataset and the bundled iOS DB with ShabadOS, Ang by Ang, and prints
each Charter S check. Read-only; never changes scripture.

    gh release download shabados-database-4.8.7 --repo Algorythmos-AI/sggs-source --dir ref
    (cd ref && shasum -a 256 -c SHA256SUMS)
    python3 -I ios/tools/scripture_crosscheck.py db/sggs.sqlite ios/Resources/sggs-ios.sqlite ref/database.sqlite

The ASCII -> Unicode map is the one sggs-data's pipeline/shabados_ingest.py uses for the English
layer. Comparison folds ONLY documented edition/encoding differences: nukta, addak and udaat (our
edition omits them) and the source font's doubled subjoined ya. Everything else must match.
"""
import sys, sqlite3, re, unicodedata, collections, random, json
OURS, IOS, SHA = sys.argv[1:4]
CONS = set("ਕਖਗਘਙਚਛਜਝਞਟਠਡਢਣਤਥਦਧਨਪਫਬਭਮਯਰਲਵੜਸਹ"); HALANT = "੍"
DIGRAPHS = [('<>','ੴ'),('AW','ਆਂ'),('Aw','ਆ'),('AY','ਐ'),('AO','ਔ'),('aU','ਊ'),('au','ਉ'),('eI','ਈ'),('ey','ਏ'),('ie','ਇ')]
MAP = {'a':'ੳ','A':'ਅ','e':'ੲ','s':'ਸ','h':'ਹ','k':'ਕ','K':'ਖ','g':'ਗ','G':'ਘ','|':'ਙ','c':'ਚ','C':'ਛ','j':'ਜ','J':'ਝ','\\':'ਞ',
 't':'ਟ','T':'ਠ','f':'ਡ','F':'ਢ','x':'ਣ','q':'ਤ','Q':'ਥ','d':'ਦ','D':'ਧ','n':'ਨ','p':'ਪ','P':'ਫ','b':'ਬ','B':'ਭ','m':'ਮ',
 'X':'ਯ','r':'ਰ','l':'ਲ','v':'ਵ','V':'ੜ','E':'ਓ','S':'ਸ਼','z':'ਜ਼','Z':'ਗ਼','^':'ਖ਼','&':'ਫ਼','L':'ਲ਼',
 'w':'ਾ','i':'ਿ','I':'ੀ','u':'ੁ','U':'ੂ','y':'ੇ','Y':'ੈ','o':'ੋ','O':'ੌ','W':'ਾਂ','M':'ੰ','µ':'ੰ','N':'ਂ','ˆ':'ਂ','Ú':'ਃ','@':'ੑ','~':'ੱ','`':'ੱ',
 'R':'੍ਰ','®':'੍ਰ','H':'੍ਹ','Í':'੍ਵ','´':'੍ਯ','Î':'੍ਯ','ç':'੍ਚ','†':'੍ਟ','œ':'੍ਤ','˜':'੍ਨ','ü':'ੁ','¨':'ੂ','Ø':'',
 ']':'॥','[':'।','0':'੦','1':'੧','2':'੨','3':'੩','4':'੪','5':'੫','6':'੬','7':'੭','8':'੮','9':'੯',' ':' ',
 ';':'',',':'','.':'','₁':'','₂':'','₃':'','₄':'','₅':'','₆':'','₈':''}
PASS = set('ੴਆਉਊਇਈਏਐਔ') | {'ਾ','ਂ'}
unknown = collections.Counter()
def move_sihari(s):
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == 'ਿ' and i + 1 < n and s[i+1] in CONS:
            j = i + 2
            while j + 1 < n and s[j] == HALANT and s[j+1] in CONS: j += 2
            out.append(s[i+1:j]); out.append('ਿ'); i = j; continue
        out.append(c); i += 1
    return ''.join(out)
def to_unicode(a):
    for x, y in DIGRAPHS: a = a.replace(x, y)
    out = []
    for ch in a:
        if ch in PASS: out.append(ch)
        elif ch in MAP: out.append(MAP[ch])
        else: unknown[ch] += 1
    u = ''.join(out)
    return re.sub(r'\s+', ' ', unicodedata.normalize('NFC', move_sihari(u))).strip()
# Documented edition/encoding folds — NOT text corrections:
FOLD = [('ਸ਼','ਸ'),('ਖ਼','ਖ'),('ਗ਼','ਗ'),('ਜ਼','ਜ'),('ਫ਼','ਫ'),('ਲ਼','ਲ'),('ੱ',''),('ੑ','')]   # nukta/addak/udaat: our edition omits them
YA = re.compile('(?:੍ਯ)+')                                                                  # our source font doubles the subjoined ya
def strict(s):   # keeps dandas, numerals, rahao: used for markers (check 7)
    s = unicodedata.normalize('NFC', s)
    for x, y in FOLD: s = s.replace(x, y)
    return re.sub(r'\s+', ' ', YA.sub('੍ਯ', s)).strip()
def loose(s):    # line identity irrespective of markers
    return re.sub(r'[॥।\s੦-੯]+', '', strict(s))

o = sqlite3.connect(f'file:{OURS}?mode=ro&immutable=1', uri=True)
ours = collections.defaultdict(list)
for ang, lid, g in o.execute('SELECT ang, id, gurmukhi FROM lines ORDER BY id'): ours[ang].append(g)
i = sqlite3.connect(f'file:{IOS}?mode=ro&immutable=1', uri=True)
ios_lines = {lid: g for lid, g in i.execute('SELECT id, gurmukhi FROM lines')}
our_lines = {lid: g for lid, g in o.execute('SELECT id, gurmukhi FROM lines')}
print('BUNDLED iOS DB vs pinned dataset: lines', len(ios_lines), len(our_lines),
      '| byte-identical gurmukhi:', sum(ios_lines.get(k) == v for k, v in our_lines.items()), '/', len(our_lines))
s = sqlite3.connect(f'file:{SHA}?mode=ro', uri=True)
ref = collections.defaultdict(list)
for page, g in s.execute('SELECT l.source_page, l.gurmukhi FROM lines l JOIN shabads sh ON l.shabad_id = sh.id WHERE sh.source_id = 1 ORDER BY l.order_id'):
    ref[page].append(to_unicode(g))
print('unknown ASCII in reference:', dict(unknown) or 'none')

# Whole-corpus agreement, Ang by Ang (multiset of loose lines; neighbour Angs allowed for page-break lines)
tot = agree = 0; worst = []
for ang in range(1, 1431):
    mine = [loose(x) for x in ours[ang]]
    pool = collections.Counter(loose(x) for a in (ang - 1, ang, ang + 1) for x in ref.get(a, []))
    miss = [m for m in mine if pool[m] == 0]
    tot += len(mine); agree += len(mine) - len(miss)
    if miss: worst.append((len(miss), ang))
print(f'WHOLE CORPUS: {agree}/{tot} lines ({100*agree/tot:.3f}%) found verbatim (after documented folds) in the reference; Angs with any unmatched line: {len(worst)}')
print('  most unmatched:', sorted(worst, reverse=True)[:12])

def show(title, ang, pick=None):
    print(f'\n== {title} (Ang {ang})')
    mine = ours[ang]; theirs = ref.get(ang, [])
    for x in (pick(mine) if pick else mine): print('  ours :', x, '| in ref (strict):', strict(x) in {strict(t) for t in theirs})
    return mine, theirs

m, t = show('Check 1 Mool Mantar + Japji start', 1, lambda L: L[:4])
print('  ref  :', t[:4])
m, t = show('Check 2 Ang 712 heading', 712, lambda L: [x for x in L if 'ਟੋਡੀ ਮਹਲਾ ੫ ਘਰੁ ੨' in x or x.startswith('ੴ')])
o2 = sqlite3.connect(f'file:{OURS}?mode=ro&immutable=1', uri=True)
hdr = o2.execute("SELECT id, comp_id, is_header, gurmukhi FROM lines WHERE ang=712 AND gurmukhi LIKE 'ਟੋਡੀ ਮਹਲਾ ੫ ਘਰੁ ੨%'").fetchall()
for lid, cid, ih, g in hdr:
    seq = [r[0] for r in o2.execute('SELECT gurmukhi FROM lines WHERE comp_id=? ORDER BY id LIMIT 3', (cid,))]
    print('  comp', cid, 'header', ih, '-> first lines of its composition:', seq)
m, t = show('Check 3 Ang 1256 refrain', 1256)
cm = collections.Counter(loose(x) for x in m); ct = collections.Counter(loose(x) for x in t)
print('  repeated in ours:', [ (k[:30], v) for k, v in cm.items() if v > 1], '| in ref:', [ (k[:30], v) for k, v in ct.items() if v > 1])
m, t = show('Check 4 Ang 1400 words', 1400, lambda L: [x for x in L if 'ਜਲ੍ਯ੍ਯਨ' in x or 'ਧਰ੍ਯ੍ਯਉ' in x])
print('  codepoints ਜਲ੍ਯ੍ਯਨ:', ' '.join(f'U+{ord(c):04X}' for c in 'ਜਲ੍ਯ੍ਯਨ'), '| ref word:', [w for x in t for w in x.split() if w.startswith('ਜਲ')][:1])
m, t = show('Check 5 Ang 1430 last lines', 1430, lambda L: L[-3:])
print('  ref last:', t[-3:])
rng = random.Random(20261017); sample = sorted(rng.sample(range(1, 1431), 5))
print('\n== Check 6 seeded random Angs', sample)
for a in sample:
    mine = ours[a]; theirs = {strict(x) for x in ref.get(a, []) + ref.get(a - 1, []) + ref.get(a + 1, [])}
    ok = sum(strict(x) in theirs for x in mine)
    print(f'  Ang {a}: {ok}/{len(mine)} lines identical incl. markers | first: {mine[1] if len(mine) > 1 else mine[0]}')
print('\n== Check 7 markers (strict compare keeps ॥ ੧ ਰਹਾਉ) on the Charter Angs')
for a in (1, 712, 1256, 1400, 1430):
    theirs = {strict(x) for x in ref.get(a, []) + ref.get(a - 1, []) + ref.get(a + 1, [])}
    bad = [x for x in ours[a] if strict(x) not in theirs]
    print(f'  Ang {a}: {len(ours[a]) - len(bad)}/{len(ours[a])} identical incl. markers', ('| differ: ' + ' / '.join(bad[:3])) if bad else '')
