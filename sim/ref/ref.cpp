//
// ref.cpp
//
// Headless UKNCBTL (github.com/nzeemin/ukncbtl-qt, emubase), the reference
// the Verilator model is compared with: runs the machine from power-on and
// writes chosen frames as PPM, drawn from the line table as UKNCBTL's
// screen view does it.
//
//   ref ROM DISK FRAMES EVERY [options...]
//
// ROM         the PPU ROM (uknc_rom.bin)
// DISK        the floppy in drive 0, '-' for none
// FRAMES      how many frames to run; EVERY: write one frame in this many
//
// options:
//   F:CODE      press a key at frame F (UKNC key code, octal), let it go
//               KEY_HOLD_FRAMES later
//   t=F:TEXT    type TEXT from frame F: letters, digits, space . , / - ; :
//               '|' is ВВОД, {ooo} an octal key code, '^' holds НР for the
//               next character
//   c1=PATH     a 24 KB ROM cartridge in slot 1; c2=PATH in slot 2
//   h1=PATH     a hard disk image on the IDE cartridge in slot 1
//
#include "stdafx.h"
#include "emubase/Emubase.h"
#include <vector>

static const int W = 640, H = 288;
static const int KEY_HOLD_FRAMES = 4;
static const int ROM_BYTES = 32256;
static const int ROM_BUFFER = 32768;
static const int CART_BYTES = 24576;
static const int FIRST_LINE = 19, LAST_LINE = 307;
static const uint16_t LINE_TABLE = 0270;

static const uint32_t COLORS[16 * 8] = {
#include "colors.inc"
};

static void render(CMotherboard* b, uint32_t* bits)
{
    uint8_t cursorYRGB = 0; bool okCursorType = false; uint8_t cursorPos = 128;
    bool cursorOn = false; uint8_t cursorAddress = 0;
    uint16_t address = LINE_TABLE;
    bool okTagSize = false, okTagType = false;
    int scale = 1; uint32_t palette = 0; uint32_t cur[8] = {0}; uint8_t pbpgpr = 0;
    for (int yy = 0; yy < LAST_LINE; yy++) {
        if (okTagSize) {
            uint16_t tag1 = b->GetRAMWord(0, address); address += 2;
            uint16_t tag2 = b->GetRAMWord(0, address); address += 2;
            if (okTagType) palette = MAKELONG(tag1, tag2);
            else {
                scale = (tag2 >> 4) & 3;
                pbpgpr = (uint8_t)((7 - (tag2 & 7)) << 4);
                cursorYRGB = tag1 & 15; okCursorType = (tag1 & 16) != 0;
                cursorPos = ((tag1 >> 8) >> scale) & 0x7f;
                cursorAddress = (tag1 >> 5) & 7;
                scale = 1 << scale;
            }
            for (int c = 0; c < 8; c++) cur[c] = COLORS[pbpgpr | ((palette >> (c << 2)) & 15)];
        }
        uint16_t addressBits = b->GetRAMWord(0, address); address += 2;
        uint16_t tagB = b->GetRAMWord(0, address);
        okTagSize = (tagB & 2) != 0;
        if (okTagSize) { address = tagB & ~7; okTagType = (tagB & 4) != 0; }
        else address = tagB & ~3;
        if (tagB & 1) cursorOn = !cursorOn;
        if (yy < FIRST_LINE) continue;
        uint32_t* p = bits + (yy - FIRST_LINE) * W;
        int xr = W, pos = 0;
        for (;;) {
            uint8_t s0 = b->GetRAMByte(0, addressBits), s1 = b->GetRAMByte(1, addressBits), s2 = b->GetRAMByte(2, addressBits);
            for (int bit = 0; bit < 8; bit++) {
                uint32_t v;
                if (cursorOn && pos == cursorPos && (!okCursorType || bit == cursorAddress)) v = COLORS[cursorYRGB];
                else v = cur[(s0 & 1) | ((s1 & 1) << 1) | ((s2 & 1) << 2)];
                for (int s = 0; s < scale && xr > 0; s++, xr--) *p++ = v;
                s0 >>= 1; s1 >>= 1; s2 >>= 1;
            }
            if (xr <= 0) break;
            addressBits++; pos++;
        }
    }
}

// UKNC key codes for typed text: letters, digits and a few signs; '|' is
// ВВОД, {ooo} an octal key code, '^' holds НР for the next character.
static int uknc_of(char c)
{
    static const uint8_t letters[26] = {
        072,076,050,057,033,047,055,0156,073,027,052,056,0112,
        054,075,053,067,074,0111,0114,051,0137,071,0115,070,0157 };
    static const uint8_t digits[10] = { 0176,030,031,032,013,034,035,016,017,0177 };
    if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
    if (c >= 'A' && c <= 'Z') return letters[c - 'A'];
    if (c >= '0' && c <= '9') return digits[c - '0'];
    switch (c) {
    case ' ': return 0113; case '.': return 0135; case ',': return 0117;
    case '/': return 0173; case '-': return 0175; case ';': return 007;
    case ':': return 0174; case '|': return 0153;
    }
    return -1;
}

static const int TYPE_HOLD_FRAMES = 2, TYPE_STEP_FRAMES = 4;
static const int KEY_SHIFT = 0105;

int main(int argc, char** argv)
{
    if (argc < 5) {
        fprintf(stderr, "usage: ref ROM DISK FRAMES EVERY [F:SCAN] [t=F:TEXT] [c1=CART] [c2=CART] [h1=HDD]\n");
        return 1;
    }
    int frames = atoi(argv[3]), every = atoi(argv[4]);
    struct Ev { int f; int scan; bool down; };
    std::vector<Ev> ev;
    const char* carts[2] = {nullptr, nullptr}; const char* hdd = nullptr;
    for (int i = 5; i < argc; i++) {
        const char* a = argv[i]; int f, n = 0; unsigned sc;
        if (!strncmp(a, "c1=", 3)) carts[0] = a + 3;
        else if (!strncmp(a, "c2=", 3)) carts[1] = a + 3;
        else if (!strncmp(a, "h1=", 3)) hdd = a + 3;
        else if (!strncmp(a, "t=", 2) && sscanf(a + 2, "%d:%n", &f, &n) == 1 && n) {
            bool shift = false;
            for (const char* c = a + 2 + n; *c; c++) {
                int code;
                if (*c == '^') { shift = true; continue; }
                if (*c == '{') { code = (int)strtol(c + 1, (char**)&c, 8); }
                else code = uknc_of(*c);
                if (code < 0) { fprintf(stderr, "can't type '%c'\n", *c); return 1; }
                if (shift) ev.push_back({f, KEY_SHIFT, true});
                ev.push_back({f + 1, code, true});
                ev.push_back({f + 1 + TYPE_HOLD_FRAMES, code, false});
                if (shift) ev.push_back({f + 2 + TYPE_HOLD_FRAMES, KEY_SHIFT, false});
                shift = false;
                f += TYPE_STEP_FRAMES + 1;
            }
        }
        else if (sscanf(a, "%d:%o", &f, &sc) == 2) { ev.push_back({f, (int)sc, true}); ev.push_back({f + KEY_HOLD_FRAMES, (int)sc, false}); }
    }

    CProcessor::Init();
    CMotherboard* b = new CMotherboard();
    uint8_t rom[ROM_BUFFER] = {0};
    FILE* f = fopen(argv[1], "rb");
    if (!f || fread(rom, 1, ROM_BYTES, f) != (size_t)ROM_BYTES) { perror(argv[1]); return 1; }
    fclose(f);
    b->LoadROM(rom);
    for (int c = 0; c < 2; c++) if (carts[c]) {
        static uint8_t cbuf[CART_BYTES];
        FILE* cf = fopen(carts[c], "rb");
        if (!cf || fread(cbuf, 1, CART_BYTES, cf) != (size_t)CART_BYTES) { perror(carts[c]); return 1; }
        fclose(cf);
        b->LoadROMCartridge(c + 1, cbuf);
    }
    b->Reset();
    if (strcmp(argv[2], "-") && !b->AttachFloppyImage(0, argv[2])) { fprintf(stderr, "can't attach %s\n", argv[2]); return 1; }
    if (hdd && !b->AttachHardImage(1, hdd)) { fprintf(stderr, "can't attach %s\n", hdd); return 1; }
    b->SetCPUBreakpoints(nullptr); b->SetPPUBreakpoints(nullptr);

    std::vector<uint32_t> bits(W * H);
    for (int fr = 0; fr < frames; fr++) {
        for (auto& e : ev) if (e.f == fr) b->KeyboardEvent((uint8_t)e.scan, e.down);
        b->SystemFrame();
        if (fr % every == every - 1) {
            render(b, bits.data());
            char name[64]; snprintf(name, sizeof name, "ref%04d.ppm", fr);
            FILE* o = fopen(name, "wb");
            fprintf(o, "P6\n%d %d\n255\n", W, H);
            for (uint32_t v : bits) { fputc(v >> 16 & 255, o); fputc(v >> 8 & 255, o); fputc(v & 255, o); }
            fclose(o);
        }
    }
    // detaching writes the images' changes back
    if (strcmp(argv[2], "-")) b->DetachFloppyImage(0);
    if (hdd) b->DetachHardImage(1);
    return 0;
}
