"""Costruisce file .xls sintetici (stessa logica del costruttore in SiciliaHostTests/XlsReaderTests.swift) e li rilegge
con il riferimento Python: verifica che il costruttore dei test e l'algoritmo di lettura siano coerenti.
Uso: python tools/xls_builder_check.py   (nessun file personale necessario)"""
import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xls_proto import read_rows
le16=lambda v: struct.pack('<H', v & 0xFFFF); le32=lambda v: struct.pack('<I', v & 0xFFFFFFFF)
def record(i,d): return le16(i)+le16(len(d))+bytes(d)
def sst_string(s):
    comp = all(ord(c)<256 for c in s)
    head = le16(len(s)) + bytes([0 if comp else 1])
    chars = bytes(ord(c) for c in s) if comp else s.encode('utf-16le')
    return head+chars, len(head), comp
def make_workbook(rows, split=True, padding=0):
    unique=[]
    for r in rows:
        for c in r:
            if isinstance(c,str) and c not in unique: unique.append(c)
    enc=[sst_string(u) for u in unique]
    payload=le32(len(unique))+le32(len(unique)); starts=[]
    for b,cs,_ in enc: starts.append(len(payload)+cs); payload+=b
    cands=[i for i in range(len(unique)) if enc[i][2] and len(unique[i])>=6]
    if split and cands:
        L=max(cands,key=lambda i:len(unique[i])); cut=starts[L]+3
        sst=record(0xFC,payload[:cut])+record(0x3C,bytes([0])+payload[cut:])
    else: sst=record(0xFC,payload)
    def globals_(off): return record(0x809,bytes(16))+record(0x85,le32(off)+bytes([0,0,6])+b'Sheet1')+sst+record(0x0A,b'')
    off=len(globals_(0)); sheet=record(0x809,bytes(16))
    for r,row in enumerate(rows):
        for c,cell in enumerate(row):
            if isinstance(cell,str): sheet+=record(0xFD,le16(r)+le16(c)+le16(0)+le32(unique.index(cell)))
            else:
                if cell==int(cell) and 0<=cell<536870911 and c%2==0: sheet+=record(0x27E,le16(r)+le16(c)+le16(0)+le32((int(cell)<<2)|2))
                else: sheet+=record(0x203,le16(r)+le16(c)+le16(0)+struct.pack('<d',cell))
    sheet+=record(0x0A,b'')
    tail=record(0xFFF,bytes([0xAB])*padding) if padding else b''
    return globals_(off)+sheet+tail
def make_ole2(stream):
    ss=512; data=bytearray(stream)
    while len(data)%ss or not data: data.append(0)
    n=len(data)//ss
    h=bytearray(512)
    def put(b,o): h[o:o+len(b)]=b
    put(bytes([0xD0,0xCF,0x11,0xE0,0xA1,0xB1,0x1A,0xE1]),0); put(le16(0x3E),24); put(le16(3),26); put(le16(0xFFFE),28)
    put(le16(9),30); put(le16(6),32); put(le32(1),44); put(le32(1),48); put(le32(4096 if len(stream)>=4096 else 0),56)
    put(le32(0xFFFFFFFE),60); put(le32(0),64); put(le32(0xFFFFFFFE),68); put(le32(0),72); put(le32(0),76)
    for i in range(1,109): put(le32(0xFFFFFFFF),76+4*i)
    fat=[0xFFFFFFFF]*128; fat[0]=0xFFFFFFFD; fat[1]=0xFFFFFFFE
    for i in range(n): fat[2+i]=0xFFFFFFFE if i==n-1 else 2+i+1
    fs=b''.join(le32(x) for x in fat)
    def de(name,t,start,size):
        e=bytearray(128); u=name.encode('utf-16le'); e[:len(u)]=u; e[64:66]=le16(len(u)+2); e[66]=t; e[116:120]=le32(start); e[120:124]=le32(size); return bytes(e)
    d=de('Root Entry',5,0xFFFFFFFE,0)+de('Workbook',2,2,len(stream)); d+=bytes(512-len(d))
    return bytes(h)+fs+d+bytes(data)
tests = {
 'numbers': [["Stato","N\u00b0 di prenotazione","Prezzo"],["ok",5100000001.0,"968 EUR"],["ok",12.0,174.24]],
 'split': [["ok","Approximate time of arrival","fine"]],
 'wide': [["Prezzo \u20ac","  spazi  ","Z\u00fcrich"]],
 'short': [["a","b","c"],["x"]],
}
for name,rows in tests.items():
    for split in (True,False):
        print(name, split, read_rows(make_ole2(make_workbook(rows,split))))
print('large', read_rows(make_ole2(make_workbook([["ok","grande"]],True,6000))))
