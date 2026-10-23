#!/usr/bin/env python3
#
# regress.py
#
# Regression runs of the Verilator model: each test boots the core with
# some images, types or presses something and checks what comes out -
# a frame or a written image - against the reference, headless UKNCBTL
# (ref/), where it can run the same thing, and against the frame hashes
# kept in regress.golden where it cannot.
#
#   ./regress.py --images DIR [--ukncbtl DIR] [--jobs N] [--long]
#                [--update] [TEST...]
#
# --images     where the software is (none of it is in the repository):
#              BASERT11.DSK      RT-11 from tang-uknc
#              UKPAL.SAV         the palette test
#              WD.SYS WDX.SAV WDR.SAV WDBOOT.SAV
#                                Oleg H.'s WD driver and tools
#              ide_wdromv0110.bin
#                                his WD ROM, as a 24 KB cartridge
#              bappwd.img        blairecas' Bad Apple, WD hard disk
# --ukncbtl    a clone of github.com/nzeemin/ukncbtl-qt: builds ref/ and
#              takes its uknc_rom.bin; without it the tests that compare
#              with UKNCBTL are skipped
# --long       also the tests that run for thousands of frames
# --update     write the golden hashes of the tests run instead of
#              checking them
#
# The model is obj_dir/Vsim_top (make first); runs go to regress_out/.
#
import argparse
import hashlib
import os
import shutil
import struct
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
SIM = os.path.join(HERE, 'obj_dir', 'Vsim_top')
RTL = os.path.join(HERE, '..', 'rtl')
REF_DIR = os.path.join(HERE, 'ref')
GOLDEN = os.path.join(HERE, 'regress.golden')
OUT = os.path.join(HERE, 'regress_out')

# ---------------------------------------------------------------------
# RT-11 volumes: add a file to the first directory segment, change a file
# ---------------------------------------------------------------------
BLOCK = 512
DIR_BLOCK = 6
SEG_BLOCKS = 2
ENTRY_WORDS = 7
E_EMPTY, E_PERM, E_EOS = 0o1000, 0o2000, 0o4000
SEG_HEADER_WORDS = 5
R50 = ' ABCDEFGHIJKLMNOPQRSTUVWXYZ$.%0123456789'


def r50(s):
    s = (s + '   ')[:3]
    return (R50.index(s[0]) * 40 + R50.index(s[1])) * 40 + R50.index(s[2])


def r50name(name):
    base, ext = (name.upper().split('.') + [''])[:2]
    base = (base + '      ')[:6]
    return [r50(base[:3]), r50(base[3:]), r50(ext)]


def rt11_entries(img):
    off = DIR_BLOCK * BLOCK
    extra, start = struct.unpack_from('<HH', img, off + 6)
    p, blk = off + 2 * SEG_HEADER_WORDS, start
    while True:
        status, = struct.unpack_from('<H', img, p)
        if status & E_EOS:
            return
        w = struct.unpack_from('<%dH' % ENTRY_WORDS, img, p)
        yield p, w, blk, extra
        blk += w[4]
        p += 2 * ENTRY_WORDS + extra


def rt11_add(img, name, data):
    blocks = (len(data) + BLOCK - 1) // BLOCK
    seg = DIR_BLOCK * BLOCK
    for p, w, start, extra in list(rt11_entries(img)):
        if w[0] & E_EMPTY and w[4] >= blocks:
            esz = 2 * ENTRY_WORDS + extra
            end = p
            while not struct.unpack_from('<H', img, end)[0] & E_EOS:
                end += esz
            if end + esz + 2 > seg + SEG_BLOCKS * BLOCK:
                raise SystemExit('directory segment full')
            img[p + esz:end + esz + 2] = img[p:end + 2]
            struct.pack_into('<7H', img, p, E_PERM, *r50name(name), blocks, 0, 0)
            img[p + 2 * ENTRY_WORDS:p + esz] = bytes(extra)
            struct.pack_into('<H', img, p + esz + 8, w[4] - blocks)
            img[start * BLOCK:(start + blocks) * BLOCK] = data + bytes(blocks * BLOCK - len(data))
            return
    raise SystemExit('no room for ' + name)


def rt11_file(img, name):
    want = r50name(name)
    for p, w, start, extra in rt11_entries(img):
        if w[0] & E_PERM and list(w[1:4]) == want:
            return start, w[4]
    raise SystemExit(name + ' not on the volume')


def rt11_startup(img, commands):
    """Append command lines to STARTS.COM (one block)."""
    start, length = rt11_file(img, 'STARTS.COM')
    off = start * BLOCK
    text = bytes(img[off:off + length * BLOCK]).rstrip(b'\0')
    text += b''.join(b'\r\n' + c.encode() for c in commands) + b'\r\n'
    if len(text) > length * BLOCK:
        raise SystemExit('STARTS.COM full')
    img[off:off + length * BLOCK] = text + bytes(length * BLOCK - len(text))


# ---------------------------------------------------------------------
# A blank WD hard disk: sector 0 with the signature and the geometry,
# which is all UKNCBTL and ide.v need to take it (Hard.cpp AttachImage)
# ---------------------------------------------------------------------
HD_SIGNATURE = (0x54A9, 0xFFEF, 0xFEFF)
HD_HEADS, HD_SPT, HD_CYLINDERS = 4, 17, 240


def blank_hdd():
    img = bytearray(BLOCK * HD_HEADS * HD_SPT * HD_CYLINDERS)
    struct.pack_into('<6H', img, 0, *HD_SIGNATURE, 0, HD_SPT, HD_HEADS * HD_SPT)
    return img


# ---------------------------------------------------------------------
# Frames
# ---------------------------------------------------------------------
def load_ppm(path):
    data = open(path, 'rb').read()
    magic, size, depth, pixels = data.split(b'\n', 3)
    w, h = map(int, size.split())
    return w, h, pixels


def md5(path):
    return hashlib.md5(open(path, 'rb').read()).hexdigest()


def compare_frames(sim_path, ref_path):
    """The reference frame against the model's at the vertical offset that
    matches best: (mismatching pixels, offset)."""
    sw, sh, sp = load_ppm(sim_path)
    rw, rh, rp = load_ppm(ref_path)
    if sw != rw:
        return rw * rh, None
    row = 3 * rw
    best = None
    for dy in range(sh - rh + 1):
        bad = 0
        for y in range(rh):
            a = sp[(y + dy) * row:(y + dy + 1) * row]
            b = rp[y * row:(y + 1) * row]
            if a != b:
                bad += sum(1 for x in range(0, row, 3) if a[x:x + 3] != b[x:x + 3])
        if best is None or bad < best[0]:
            best = (bad, dy)
        if bad == 0:
            break
    return best


def cursor_span(path, line, colour):
    w, h, px = load_ppm(path)
    xs = [x for x in range(w) if px[(line * w + x) * 3:(line * w + x) * 3 + 3] == colour]
    return (xs[0], xs[-1]) if xs else None


# ---------------------------------------------------------------------
# Runs
# ---------------------------------------------------------------------
BOOT_FLOPPY = 't=130:1|'          # boot menu: 1 (disk), ВВОД
BOOT_CARTRIDGE = ['150:1E', '165:5A']   # 2 (ROM cartridge), ВВОД; PS/2 codes
STATUS_HDD_DELAY_OFF = 1 << 15


def run_sim(d, frames, every, args):
    os.makedirs(d, exist_ok=True)
    link = os.path.join(d, 'rtl')
    if not os.path.islink(link):
        os.symlink(os.path.abspath(RTL), link)
    with open(os.path.join(d, 'sim.log'), 'w') as log:
        subprocess.run([SIM, str(frames), str(every)] + args, cwd=d, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    return lambda f: os.path.join(d, 'frame%04d.ppm' % f)


def run_ref(ctx, d, frames, every, disk, args):
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'ref.log'), 'w') as log:
        subprocess.run([ctx.ref, ctx.rom, disk, str(frames), str(every)] + args, cwd=d,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    return lambda f: os.path.join(d, 'ref%04d.ppm' % f)


class Context:
    def __init__(self, images, ukncbtl):
        self.images = images
        self.ref = self.rom = None
        if ukncbtl:
            subprocess.run(['make', '-s', 'UKNCBTL=' + ukncbtl], cwd=REF_DIR, check=True)
            self.ref = os.path.join(REF_DIR, 'ref')
            self.rom = os.path.join(ukncbtl, 'emulator', 'uknc_rom.bin')

    def image(self, name):
        path = os.path.join(self.images, name)
        if not os.path.exists(path):
            raise SystemExit('missing image ' + path)
        return path

    def read(self, name):
        return bytearray(open(self.image(name), 'rb').read())


class Skip(Exception):
    pass


def need_ref(ctx):
    if not ctx.ref:
        raise Skip('no --ukncbtl')


def write(path, data):
    with open(path, 'wb') as f:
        f.write(data)
    return path


# Each test returns (name, value) pairs: a frame's or an image's hash for
# regress.golden, or None for a check that passed on its own.  A failed
# check raises AssertionError.

def t_menu(ctx, d):
    frame = run_sim(d, 100, 100, [])
    return [('frame', md5(frame(99)))]


MON_GREY, MON_GREEN = 1, 2
MON_SHIFT = 20


def t_monitor(ctx, d):
    out = []
    for mode in (MON_GREY, MON_GREEN):
        frame = run_sim(os.path.join(d, str(mode)), 100, 100,
                        ['+status=%x' % (mode << MON_SHIFT)])
        out.append(('frame%d' % mode, md5(frame(99))))
    return out


def t_rt11(ctx, d):
    frame = run_sim(d, 600, 600, ['d0=' + ctx.image('BASERT11.DSK'), BOOT_FLOPPY])
    return [('frame', md5(frame(599)))]


def ukpal_disk(ctx, d):
    os.makedirs(d, exist_ok=True)
    img = ctx.read('BASERT11.DSK')
    rt11_add(img, 'UKPAL.SAV', bytes(ctx.read('UKPAL.SAV')))
    rt11_startup(img, ['R UKPAL'])
    return write(os.path.join(d, 'ukpal.dsk'), img)


UKPAL_FRAME = 699


def t_ukpal(ctx, d):
    need_ref(ctx)
    disk = ukpal_disk(ctx, d)
    sim = run_sim(os.path.join(d, 'sim'), UKPAL_FRAME + 1, UKPAL_FRAME + 1,
                  ['d0=' + disk, BOOT_FLOPPY])
    ref_disk = write(os.path.join(d, 'ref.dsk'), open(disk, 'rb').read())
    ref = run_ref(ctx, os.path.join(d, 'ref'), UKPAL_FRAME + 1, UKPAL_FRAME + 1, ref_disk,
                  [BOOT_FLOPPY])
    bad, dy = compare_frames(sim(UKPAL_FRAME), ref(UKPAL_FRAME))
    assert bad == 0, '%d pixels differ from UKNCBTL' % bad
    return [('frame', None)]


JOY_RIGHT, JOY_B = 0x01, 0x20
CURSOR_GREY = b'\x80\x80\x80'
CURSOR_LINE = 30                  # a line of UKPAL's upper rows
CURSOR_STEP = 16                  # one cursor position at scale 2


def t_gamepad(ctx, d):
    disk = ukpal_disk(ctx, d)
    # 1 typed, ВВОД from B; then Right twice on the D-pad
    frame = run_sim(os.path.join(d, 'sim'), 700, 100,
                    ['d0=' + disk, 't=130:1', 'j140:%x' % JOY_B, 'j146:0',
                     'j600:%x' % JOY_RIGHT, 'j606:0', 'j620:%x' % JOY_RIGHT, 'j626:0'])
    span = cursor_span(frame(699), CURSOR_LINE, CURSOR_GREY)
    want = (2 * CURSOR_STEP, 3 * CURSOR_STEP - 1)
    assert span == want, 'cursor at %s, not %s' % (span, want)
    return [('cursor', None)]


FDD_COPY = 't=600:COPY SWAP.SYS X.SYS|'
FDD_FRAMES = 1100            # the model keeps the drive's timing: the copy ends near 1000


def t_fdd_write(ctx, d):
    need_ref(ctx)
    os.makedirs(d, exist_ok=True)
    img = ctx.read('BASERT11.DSK')
    disk = write(os.path.join(d, 'sim.dsk'), img)
    out = os.path.join(d, 'sim_out.dsk')
    run_sim(os.path.join(d, 'sim'), FDD_FRAMES, FDD_FRAMES, ['d0=' + disk, 'o0=' + out, BOOT_FLOPPY, FDD_COPY])
    ref_disk = write(os.path.join(d, 'ref.dsk'), img)
    run_ref(ctx, os.path.join(d, 'ref'), FDD_FRAMES, FDD_FRAMES, ref_disk, [BOOT_FLOPPY, FDD_COPY])
    a, b = open(out, 'rb').read(), open(ref_disk, 'rb').read()
    assert a != bytes(img), 'nothing was written'
    assert a == b, 'the floppy differs from UKNCBTL\'s in %d blocks' % sum(
        1 for i in range(0, len(a), BLOCK) if a[i:i + BLOCK] != b[i:i + BLOCK])
    return [('image', None)]


def t_hdd_badapple(ctx, d):
    frame = run_sim(d, 300, 300, ['d4=' + ctx.image('bappwd.img')] + BOOT_CARTRIDGE)
    return [('frame', md5(frame(299)))]


def t_cartridge(ctx, d):
    # the WD ROM loaded into slot 1 with no disk: its banner, no drive
    frame = run_sim(d, 300, 300, ['i40=' + ctx.image('ide_wdromv0110.bin')] + BOOT_CARTRIDGE)
    return [('frame', md5(frame(299)))]


# The WD tools under RT-11: partition a blank disk with WDX (one partition,
# the defaults), then INIT it, copy the system onto it and make it
# bootable.  The answers are timed for both the model and UKNCBTL.
WD_TOOLS = ['WD.SYS', 'WDX.SAV', 'WDR.SAV', 'WDBOOT.SAV']
WD_SCRIPT = [
    (650, 'R WDX|'),
    (1050, 'N|'),               # read the default block from a file
    (1150, '|'),                # clean the data
    (1300, '|'),                # autodetect
    (1450, '|'),                # the parameters are right
    (1600, '|'),                # one partition
    (1800, '|'),                # of the whole disk
    (1950, '|'),                # no partition test
    (2100, '|'),                # the timing
    (2250, '|'),                # a hidden partition
    (2550, '|'),                # its number
    (2700, '|'),                # the PP memory shift
    (2850, 'N|'),               # don't look at the data
    (3000, 'N|'),               # don't save it in a file
    (3150, 'Y|'),               # write the master block
    (3350, 'R WDR|'),
    (3500, 'LOAD WD|'),
    (3650, 'INIT WD0:|'),
    (3800, 'Y|'),
    (4150, 'COPY/SYS MZ0: WD0:|'),
    (5550, 'COPY/BOOT:WD WD0:RT11SJ WD0:|'),
]
WD_FRAMES = 6000


def t_hdd_write(ctx, d):
    need_ref(ctx)
    os.makedirs(d, exist_ok=True)
    img = ctx.read('BASERT11.DSK')
    for f in WD_TOOLS:
        rt11_add(img, f, bytes(ctx.read(f)))
    rom = ctx.image('ide_wdromv0110.bin')
    typed = ['t=%d:%s' % step for step in WD_SCRIPT]

    disk = write(os.path.join(d, 'sim.dsk'), img)
    hdd = write(os.path.join(d, 'sim.img'), blank_hdd())
    out = os.path.join(d, 'sim_out.img')
    run_sim(os.path.join(d, 'sim'), WD_FRAMES, 50,
            ['d0=' + disk, 'd4=' + hdd, 'o4=' + out, '+status=%x' % STATUS_HDD_DELAY_OFF,
             BOOT_FLOPPY] + typed)

    ref_disk = write(os.path.join(d, 'ref.dsk'), img)
    ref_hdd = write(os.path.join(d, 'ref.img'), blank_hdd())
    run_ref(ctx, os.path.join(d, 'ref'), WD_FRAMES, 50, ref_disk,
            ['c1=' + rom, 'h1=' + ref_hdd, BOOT_FLOPPY] + typed)

    a, b = open(out, 'rb').read(), open(ref_hdd, 'rb').read()
    assert a != bytes(blank_hdd()), 'nothing was written'
    assert a == b, 'the hard disk differs from UKNCBTL\'s in %d sectors' % sum(
        1 for i in range(0, len(a), BLOCK) if a[i:i + BLOCK] != b[i:i + BLOCK])
    return [('image', None)]


TESTS = {
    'menu': (t_menu, False),
    'monitor': (t_monitor, False),
    'rt11': (t_rt11, False),
    'ukpal': (t_ukpal, False),
    'gamepad': (t_gamepad, False),
    'fdd_write': (t_fdd_write, False),
    'hdd_badapple': (t_hdd_badapple, False),
    'cartridge': (t_cartridge, False),
    'hdd_write': (t_hdd_write, True),
}


def read_golden():
    golden = {}
    if os.path.exists(GOLDEN):
        for line in open(GOLDEN):
            if line.strip() and not line.startswith('#'):
                key, value = line.split()
                golden[key] = value
    return golden


def main():
    ap = argparse.ArgumentParser(description='Regression runs of the Verilator model')
    ap.add_argument('--images', required=True)
    ap.add_argument('--ukncbtl')
    ap.add_argument('--jobs', type=int, default=os.cpu_count())
    ap.add_argument('--long', action='store_true')
    ap.add_argument('--update', action='store_true')
    ap.add_argument('tests', nargs='*')
    opt = ap.parse_args()

    names = opt.tests or [n for n, (f, long_run) in TESTS.items() if opt.long or not long_run]
    for n in names:
        if n not in TESTS:
            raise SystemExit('no test ' + n)
    if not os.path.exists(SIM):
        raise SystemExit('no %s: make first' % SIM)
    ctx = Context(opt.images, opt.ukncbtl)
    shutil.rmtree(OUT, ignore_errors=True)

    def one(name):
        try:
            return name, TESTS[name][0](ctx, os.path.join(OUT, name)), None
        except Skip as e:
            return name, None, 'skipped: %s' % e
        except (AssertionError, subprocess.CalledProcessError) as e:
            return name, None, 'FAILED: %s' % e

    golden = read_golden()
    failed = 0
    with ThreadPoolExecutor(opt.jobs) as pool:
        for name, results, problem in pool.map(one, names):
            if problem:
                failed += problem.startswith('FAILED')
                print('%-14s %s' % (name, problem))
                continue
            notes = []
            for key, value in results:
                if value is None:
                    notes.append(key + ' ok')
                    continue
                gkey = name + '.' + key
                if opt.update:
                    golden[gkey] = value
                    notes.append(key + ' recorded')
                elif gkey not in golden:
                    notes.append(key + ' has no golden hash')
                elif golden[gkey] != value:
                    notes.append(key + ' CHANGED')
                    failed += 1
                else:
                    notes.append(key + ' ok')
            print('%-14s %s' % (name, ', '.join(notes)))

    if opt.update:
        with open(GOLDEN, 'w') as f:
            f.write('# regress.py --update: md5 of the frames the model drew\n')
            for key in sorted(golden):
                f.write('%s %s\n' % (key, golden[key]))
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
