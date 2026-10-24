"""tests/compat/upk_check.py -- check a UPK package independently of utasm:
its layout, every file's SHA-256, and its Ed25519 signature, the last with a
pure-Python Ed25519 written from RFC 8032 section 5.1 (not utasm's code).

Used by the upk suite (suites.upk); also runs by hand:
    python3 tests/compat/upk_check.py pkg.upk [public-key-file]
"""
import hashlib, struct, sys

# ---- Ed25519, RFC 8032 5.1 -------------------------------------------------
P = 2**255 - 19
Q = 2**252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P
SQRT_M1 = pow(2, (P - 1) // 4, P)


def _recover_x(y, sign):
    x2 = (y * y - 1) * pow(D * y * y + 1, P - 2, P)
    x = pow(x2, (P + 3) // 8, P)
    if (x * x - x2) % P:
        x = x * SQRT_M1 % P
    if (x * x - x2) % P:
        return None
    if x & 1 != sign:
        x = P - x
    return x


_GY = 4 * pow(5, P - 2, P) % P
_GX = _recover_x(_GY, 0)
G = (_GX, _GY, 1, _GX * _GY % P)


def _add(a, b):
    A = (a[1] - a[0]) * (b[1] - b[0]) % P
    B = (a[1] + a[0]) * (b[1] + b[0]) % P
    C = 2 * a[3] * b[3] * D % P
    E = 2 * a[2] * b[2] % P
    e, f, g, h = B - A, E - C, E + C, B + A
    return (e * f % P, g * h % P, f * g % P, e * h % P)


def _mul(s, pt):
    acc = (0, 1, 1, 0)
    while s:
        if s & 1:
            acc = _add(acc, pt)
        pt = _add(pt, pt)
        s >>= 1
    return acc


def _enc(pt):
    zi = pow(pt[2], P - 2, P)
    x, y = pt[0] * zi % P, pt[1] * zi % P
    return int.to_bytes(y | ((x & 1) << 255), 32, "little")


def _dec(b):
    y = int.from_bytes(b, "little") & ((1 << 255) - 1)
    x = _recover_x(y, b[31] >> 7)
    return None if x is None else (x, y, 1, x * y % P)


def ed25519_verify(pub, msg, sig):
    A, R = _dec(pub), _dec(sig[:32])
    S = int.from_bytes(sig[32:], "little")
    if A is None or R is None or S >= Q:
        return False
    k = int.from_bytes(hashlib.sha512(sig[:32] + pub + msg).digest(), "little") % Q
    return _enc(_mul(S, G)) == _enc(_add(R, _mul(k, A)))


# ---- the package --------------------------------------------------------
def check(data, pub=None):
    """-> (failures, entries): failures a list of strings, entries a list of
    (path, kind, bytes)."""
    bad = []
    if len(data) < 144:
        return ["shorter than its header"], []
    (magic, ver, hsize, flags, n, eoff, soff, ssize, moff, msize, _res,
     fsize) = struct.unpack_from("<IHHIIIIIIIIQ", data, 0)
    if magic != 0x004B5055: bad.append("magic %#x" % magic)
    if (ver, hsize) != (1, 144): bad.append("version %d / header %d" % (ver, hsize))
    if fsize != len(data): bad.append("file size %d, %d read" % (fsize, len(data)))
    if eoff != 144 or soff != 144 + 64 * n or moff != soff + ssize:
        bad.append("tables out of place")
    entries = []
    for i in range(n):
        po, kind, doff, size = struct.unpack_from("<IIQQ", data, eoff + 64 * i)
        digest = data[eoff + 64 * i + 24:eoff + 64 * i + 56]
        path = data[soff + po:data.index(b"\0", soff + po)].decode()
        body = data[doff:doff + size]
        if doff % 16: bad.append("%s not 16-aligned" % path)
        if hashlib.sha256(body).digest() != digest: bad.append("%s: SHA-256" % path)
        entries.append((path, kind, body))
    if flags & 1:
        msg = hashlib.sha256(data[:0x50] + b"\0" * 64 + data[0x90:moff + msize]).digest()
        if pub is None:
            bad.append("signed, but no public key to check it with")
        else:
            if hashlib.sha256(pub).digest() != data[0x30:0x50]:
                bad.append("signer is not the key's SHA-256")
            if not ed25519_verify(pub, msg, data[0x50:0x90]):
                bad.append("Ed25519 signature does not verify")
    elif pub is not None:
        bad.append("not signed")
    return bad, entries


if __name__ == "__main__":
    pkg = open(sys.argv[1], "rb").read()
    key = open(sys.argv[2], "rb").read() if len(sys.argv) > 2 else None
    failures, files = check(pkg, key)
    for path, kind, body in files:
        print("%-24s kind %d  %d bytes" % (path, kind, len(body)))
    print("\n".join(failures) if failures else "OK")
    sys.exit(1 if failures else 0)
