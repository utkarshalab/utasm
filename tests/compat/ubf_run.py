"""tests/compat/ubf_run.py -- a host-side UBF loader for the ubf suite: checks a UBF file as docs/UBF_SPEC.md says,
maps it into executable memory, applies its relocations, points its imports
at C library functions, and calls its entry point.

usage: python3 tests/compat/ubf_run.py image.ubf [--dump]
prints a summary; exit status = the program's return value (or 100+ on a
format error).
"""
import ctypes, hashlib, mmap, struct, sys

def fail(msg, code=100):
    print("UBF ERROR:", msg)
    sys.exit(code)

data = open(sys.argv[1], "rb").read()
dump = "--dump" in sys.argv
if len(data) < 128:
    fail("short file")
(magic, version, hsize, kind, arch, flags, mem_size, entry, stack, nseg,
 seg_off, rel_off, nrel, imp_off, nimp, exp_off, nexp, str_off, str_size,
 cpu, file_size) = struct.unpack_from("<IHHHHIQQIIIIIIIIIIIII", data, 0)
if magic != 0x00464255: fail("magic %08x" % magic)
if version != 1 or hsize != 128: fail("version/header size")
if arch != 1: fail("arch")
if file_size != len(data): fail("file_size %d != %d" % (file_size, len(data)))
digest = data[0x58:0x78]
zeroed = data[:0x58] + b"\0" * 32 + data[0x78:]
if hashlib.sha256(zeroed).digest() != digest: fail("sha256")
if mem_size % 4096: fail("mem_size not page-aligned")

def name(off):
    end = data.index(b"\0", str_off + off)
    return data[str_off + off:end].decode()

segs = [struct.unpack_from("<IIIIQQ", data, seg_off + 32 * i) for i in range(nseg)]
rels = [struct.unpack_from("<II", data, rel_off + 8 * i) for i in range(nrel)]
imps = [struct.unpack_from("<IIII", data, imp_off + 16 * i) for i in range(nimp)]
exps = [struct.unpack_from("<IIQ", data, exp_off + 16 * i) for i in range(nexp)]

def fnv(s):
    h = 0x811C9DC5
    for b in s.encode():
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
    return h

prev_end = 0
for t, prot, foff, fsize, moff, msize in segs:
    if moff % 4096: fail("segment not page-aligned")
    if moff < prev_end: fail("segments overlap")
    if fsize > msize: fail("file_size > mem_size")
    if (prot & 6) == 6: fail("W|X segment")
    want = {1: 5, 2: 1, 3: 3, 4: 3}[t]
    if prot != want: fail("prot %d for type %d" % (prot, t))
    if t == 4 and fsize: fail("bss with bytes")
    prev_end = moff + msize
if prev_end > mem_size: fail("segments past mem_size")
for imp in imps:
    if fnv(name(imp[0])) != imp[1]: fail("import hash " + name(imp[0]))
for e in exps:
    if fnv(name(e[0])) != e[1]: fail("export hash " + name(e[0]))

print("kind=%d flags=%d mem=%#x entry=%#x segs=%d rels=%d imports=%s exports=%s" % (
    kind, flags, mem_size, entry, nseg, nrel,
    ",".join(name(i[0]) for i in imps), ",".join(name(e[0]) for e in exps)))
if dump:
    for s in segs: print("  seg type=%d prot=%d foff=%#x fsize=%#x moff=%#x msize=%#x" % s)

# ---- load ----
buf = mmap.mmap(-1, mem_size, prot=mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC)
base = ctypes.addressof(ctypes.c_char.from_buffer(buf))
for t, prot, foff, fsize, moff, msize in segs:
    buf[moff:moff + fsize] = data[foff:foff + fsize]
for off, typ in rels:
    if typ != 1: fail("relocation type %d" % typ)
    v = struct.unpack_from("<Q", buf, off)[0]
    struct.pack_into("<Q", buf, off, (v + base) & 0xFFFFFFFFFFFFFFFF)
libc = ctypes.CDLL(None)
for name_off, h, slot, fl in imps:
    fn = getattr(libc, name(name_off))
    struct.pack_into("<Q", buf, slot, ctypes.cast(fn, ctypes.c_void_p).value)
if not flags & 1:
    print("library: not run")
    sys.exit(0)
sys.stdout.flush()
rc = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)(base + entry)(None)
print("returned", rc)
sys.exit(rc & 0xFF)
