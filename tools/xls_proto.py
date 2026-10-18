"""Riferimento Python del lettore .xls (OLE2 + BIFF8) portato in `SiciliaHost/Core/Logic/XlsReader.swift`.

Uso (controllo sui file reali di Booking, che contengono dati personali e NON stanno in repo):
    python tools/xls_proto.py "../Androidapp/Arrivo con recapiti_ 2026-01-01 - 2026-07-30.xls" ../Androidapp/resocontociuririvu.xls
Stampa righe x colonne, l'intestazione e la prima riga. Atteso: 31, 40 e 44 righe x 26 colonne.
Se si cambia XlsReader.swift, riallineare questo file e rieseguire il controllo."""
import struct, sys

def u16(b, o): return struct.unpack_from('<H', b, o)[0]
def u32(b, o): return struct.unpack_from('<I', b, o)[0]

class Ole2:
    def __init__(self, data):
        if data[:8] != bytes([0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1]): raise ValueError('non OLE2')
        self.d = data
        self.ss = 1 << u16(data, 30)          # sector size
        self.mss = 1 << u16(data, 32)         # mini sector size
        nfat = u32(data, 44); dir0 = u32(data, 48); self.cutoff = u32(data, 56)
        minifat0 = u32(data, 60); nminifat = u32(data, 64); difat0 = u32(data, 68); ndifat = u32(data, 72)
        difat = [u32(data, 76 + 4*i) for i in range(109)]
        s = difat0
        for _ in range(ndifat):
            off = self.so(s)
            for i in range(self.ss//4 - 1): difat.append(u32(data, off + 4*i))
            s = u32(data, off + self.ss - 4)
        self.fat = []
        for sid in difat[:nfat]:
            off = self.so(sid)
            self.fat += [u32(data, off + 4*i) for i in range(self.ss//4)]
        # directory
        dirdata = self.chain(dir0)
        self.entries = []
        for i in range(len(dirdata)//128):
            e = dirdata[i*128:(i+1)*128]
            nlen = u16(e, 64)
            name = e[:max(nlen-2,0)].decode('utf-16le', 'replace')
            self.entries.append((name, e[66], u32(e, 116), u32(e, 120)))
        root = self.entries[0]
        self.ministream = self.chain(root[2])[:root[3]] if root[2] < 0xFFFFFFF0 else b''
        mf = self.chain(minifat0) if nminifat else b''
        self.minifat = [u32(mf, 4*i) for i in range(len(mf)//4)]
    def so(self, sid): return 512 + sid * self.ss
    def chain(self, start):
        out = bytearray(); seen = set(); s = start
        while s < 0xFFFFFFF0 and s not in seen:
            seen.add(s); out += self.d[self.so(s):self.so(s)+self.ss]; s = self.fat[s]
        return bytes(out)
    def minichain(self, start, size):
        out = bytearray(); seen = set(); s = start
        while s < 0xFFFFFFF0 and s not in seen:
            seen.add(s); out += self.ministream[s*self.mss:(s+1)*self.mss]; s = self.minifat[s]
        return bytes(out[:size])
    def stream(self, names):
        for name, typ, start, size in self.entries:
            if typ == 2 and name in names:
                return self.chain(start)[:size] if size >= self.cutoff else self.minichain(start, size)
        raise ValueError('stream Workbook non trovato')

def records(b):
    o = 0
    while o + 4 <= len(b):
        rid, ln = u16(b, o), u16(b, o+2)
        yield o, rid, b[o+4:o+4+ln]
        o += 4 + ln

def read_sst(b, start_off):
    """Raccoglie dati SST + CONTINUE come lista di chunk (per gestire le stringhe spezzate)."""
    chunks = []
    for off, rid, data in records(b[start_off:]):
        if rid == 0x00FC: chunks.append(data)
        elif rid == 0x003C and chunks: chunks.append(data)
        elif chunks: break
    return chunks

class Cursor:
    def __init__(self, chunks): self.chunks = chunks; self.ci = 0; self.pos = 0
    def left(self): return len(self.chunks[self.ci]) - self.pos
    def next_chunk(self): self.ci += 1; self.pos = 0
    def take(self, n):
        out = bytearray()
        while n > 0:
            if self.left() == 0: self.next_chunk()
            k = min(n, self.left()); out += self.chunks[self.ci][self.pos:self.pos+k]; self.pos += k; n -= k
        return bytes(out)
    def skip(self, n): self.take(n)

def parse_sst(chunks):
    c = Cursor(chunks)
    c.skip(4); unique = u32(c.take(4), 0)
    out = []
    for _ in range(unique):
        cch = u16(c.take(2), 0); flags = c.take(1)[0]
        wide = flags & 1; ext = flags & 4; rich = flags & 8
        runs = u16(c.take(2), 0) if rich else 0
        extlen = u32(c.take(4), 0) if ext else 0
        chars = []; remaining = cch
        while remaining > 0:
            if c.left() == 0:
                c.next_chunk(); wide = c.take(1)[0] & 1     # nuovo byte flags a inizio CONTINUE
            avail = c.left() // (2 if wide else 1)
            k = min(remaining, avail)
            raw = c.take(k * (2 if wide else 1))
            chars.append(raw.decode('utf-16le') if wide else raw.decode('latin-1'))
            remaining -= k
        c.skip(4*runs + extlen)
        out.append(''.join(chars))
    return out

def rk(v):
    if v & 2: n = float(struct.unpack('<i', struct.pack('<I', v))[0] >> 2)
    else: n = struct.unpack('<d', struct.pack('<Q', (v & 0xFFFFFFFC) << 32))[0]
    return n / 100 if v & 1 else n

def num_text(d):
    if d == int(d) and abs(d) != float('inf'): return str(int(d))
    return repr(d)

def read_rows(data):
    wb = Ole2(data).stream({'Workbook', 'Book'})
    sst = []; sheet0 = None
    for off, rid, rec in records(wb):
        if rid == 0x0085 and sheet0 is None: sheet0 = u32(rec, 0)
        elif rid == 0x00FC:
            sst = parse_sst(read_sst(wb, off))
    cells = {}
    first = True
    for off, rid, rec in records(wb[sheet0:]):
        if rid == 0x0809 and not first: break
        if rid == 0x0809: first = False; continue
        if rid == 0x000A: break
        if rid == 0x00FD:  r, c, _, i = struct.unpack_from('<HHHI', rec); cells[(r,c)] = sst[i].strip() if i < len(sst) else ''
        elif rid == 0x0203: r, c, _ = struct.unpack_from('<HHH', rec); cells[(r,c)] = num_text(struct.unpack_from('<d', rec, 6)[0])
        elif rid == 0x027E: r, c, _, v = struct.unpack_from('<HHHI', rec); cells[(r,c)] = num_text(rk(v))
        elif rid == 0x00BD:
            r, c0 = struct.unpack_from('<HH', rec); n = (len(rec) - 6) // 6
            for k in range(n): cells[(r, c0+k)] = num_text(rk(u32(rec, 4 + 6*k + 2)))
        elif rid == 0x0204:
            r, c, _, ln = struct.unpack_from('<HHHH', rec); fl = rec[8]
            cells[(r,c)] = (rec[9:9+2*ln].decode('utf-16le') if fl & 1 else rec[9:9+ln].decode('latin-1')).strip()
    if not cells: return []
    maxr = max(r for r,_ in cells); maxc = max(c for _,c in cells)
    return [[cells.get((r,c), '') for c in range(maxc+1)] for r in range(maxr+1)]

if __name__ == '__main__':
    for p in sys.argv[1:]:
        rows = read_rows(open(p,'rb').read())
        print(p.split('\\')[-1], len(rows), 'righe x', len(rows[0]) if rows else 0)
        print(rows[0]); print(rows[1] if len(rows) > 1 else '')
