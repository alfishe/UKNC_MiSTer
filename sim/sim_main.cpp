//
// sim_main.cpp
//
// Runs the core from power-on and writes chosen frames as PPM files.
//
//   obj_dir/Vsim_top frames every [options...]
//
// frames      how many frames to run (50 a second)
// every       write one frame in this many
//
// options:
//   F:KEY       press a key at frame F, let it go KEY_HOLD_FRAMES later; KEY
//               is a PS/2 set 2 code in hex, E0xx for an extended one
//   t=F:TEXT    type TEXT from frame F: letters, digits, space . , / - ;
//               '|' is Enter
//   jF:HEX      set the gamepad's buttons (hps_io joystick_0 bits) at frame F
//   dN=PATH     put an image in slot N: 0-3 the floppy drives, 4 the
//               hard disk
//   oN=PATH     write slot N's image to PATH at the end
//   lat=US      the HPS's delay before a sector transfer (default 200 us)
//   +sdlog      print every sector transfer
//
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include "Vsim_top.h"
#include "verilated.h"

static const int  RESET_CYCLES     = 100;
static const int  MAX_W            = 1024;
static const int  MAX_H            = 1024;
static const int  KEY_HOLD_FRAMES  = 5;
static const int  TYPE_HOLD_FRAMES = 2;   // a typed key is down this long
static const int  TYPE_STEP_FRAMES = 4;   // and the next one comes this much later
static const int  EXT_PREFIX       = 0xE0;
static const char ENTER_CHAR       = '|';

static const long CLK_HZ           = 50000000;
static const int  DEFAULT_LAT_US   = 200;
static const int  DRIVES           = 5;   // image slots
static const int  HDD              = 4;
static const int  SECTOR_WORDS     = 256;
static const int  SECTOR_BYTES     = 512;
static const int  WORD_CYCLES      = 4;   // clk_sys cycles per buffer word
static const int  GAP_CYCLES       = 50;  // between two transfers

// hps_io's ps2_key: [10] toggles per event, [9] pressed, [8] extended
static const int PS2_TOGGLE  = 1 << 10;
static const int PS2_PRESSED = 1 << 9;
static const int PS2_EXT     = 1 << 8;

static const int PS2_ENTER   = 0x5A;

struct KeyEvent { int frame; int code; bool pressed; };
struct PadEvent { int frame; unsigned buttons; };

static int ps2_of(char c)
{
   static const unsigned char letters[26] = {
      0x1C,0x32,0x21,0x23,0x24,0x2B,0x34,0x33,0x43,0x3B,0x42,0x4B,0x3A,
      0x31,0x44,0x4D,0x15,0x2D,0x1B,0x2C,0x3C,0x2A,0x1D,0x22,0x35,0x1A };
   static const unsigned char digits[10] = {
      0x45,0x16,0x1E,0x26,0x25,0x2E,0x36,0x3D,0x3E,0x46 };
   if(c >= 'a' && c <= 'z') c -= 'a' - 'A';
   if(c >= 'A' && c <= 'Z') return letters[c - 'A'];
   if(c >= '0' && c <= '9') return digits[c - '0'];
   switch(c) {
   case ' ': return 0x29;
   case '.': return 0x49;
   case ',': return 0x41;
   case '/': return 0x4A;
   case '-': return 0x4E;
   case ENTER_CHAR: return PS2_ENTER;
   }
   return 0;
}

// The HPS side of the sector interface
struct Disk {
   std::vector<unsigned char> data;
   std::string save;
};

enum HpsState { HPS_IDLE, HPS_LATENCY, HPS_READ, HPS_WRITE, HPS_GAP };

struct Hps {
   Disk     disk[DRIVES];
   HpsState state = HPS_IDLE;
   long     wait = 0;
   long     latency = 0;
   int      drive = 0, word = 0, phase = 0;
   unsigned lba = 0;
   bool     log = false;
   long     reads = 0, writes = 0;

   unsigned char *sector()
   {
      size_t off = (size_t)lba * SECTOR_BYTES;
      return off + SECTOR_BYTES <= disk[drive].data.size() ? &disk[drive].data[off] : nullptr;
   }

   // one clk_sys cycle, before the rising edge
   void step(Vsim_top *top)
   {
      top->sd_buff_wr = 0;
      switch(state) {
      case HPS_IDLE: {
         int req = top->sd_rd | top->sd_wr;
         for(int i = 0; i < DRIVES; i++) if((req >> i) & 1 && !disk[i].data.empty()) {
            drive = i;
            lba   = i == HDD ? top->sd_lba_hdd : top->sd_lba;
            state = HPS_LATENCY;
            wait  = latency;
            phase = (top->sd_wr >> i) & 1;   // remember the direction
            break;
         }
         break;
      }
      case HPS_LATENCY:
         if(--wait > 0) break;
         top->sd_ack = 1 << drive;
         word  = 0;
         state = phase ? HPS_WRITE : HPS_READ;
         phase = 0;
         if(log) printf("sd %s drive %d lba %u\n", state == HPS_WRITE ? "write" : "read", drive, lba);
         break;
      case HPS_READ: {
         unsigned char *s = sector();
         if(phase == 0) {
            top->sd_buff_addr = word;
            top->sd_buff_dout = s ? s[word * 2] | s[word * 2 + 1] << 8 : 0;
            top->sd_buff_wr   = 1;
         }
         if(++phase == WORD_CYCLES) {
            phase = 0;
            if(++word == SECTOR_WORDS) { top->sd_ack = 0; state = HPS_GAP; wait = GAP_CYCLES; reads++; }
         }
         break;
      }
      case HPS_WRITE: {
         if(phase == 0) top->sd_buff_addr = word;
         if(++phase == WORD_CYCLES) {
            unsigned char *s = sector();
            unsigned din = drive == HDD ? top->sd_buff_din_hdd : top->sd_buff_din;
            if(s) { s[word * 2] = din & 0xFF; s[word * 2 + 1] = din >> 8; }
            phase = 0;
            if(++word == SECTOR_WORDS) { top->sd_ack = 0; state = HPS_GAP; wait = GAP_CYCLES; writes++; }
         }
         break;
      }
      case HPS_GAP:
         if(--wait == 0) state = HPS_IDLE;
         break;
      }
   }
};

int main(int argc, char **argv)
{
   Verilated::commandArgs(argc, argv);
   if(argc < 3) { fprintf(stderr, "usage: %s frames every [options]\n", argv[0]); return 1; }
   const int frames = atoi(argv[1]);
   const int every  = atoi(argv[2]);

   Hps hps;
   int lat_us = DEFAULT_LAT_US;
   std::vector<KeyEvent> keys;
   std::vector<PadEvent> pads;

   for(int i = 3; i < argc; i++) {
      const char *a = argv[i];
      int f, k, n;
      if(!strcmp(a, "+sdlog")) hps.log = true;
      else if(!strncmp(a, "lat=", 4)) lat_us = atoi(a + 4);
      else if((a[0] == 'd' || a[0] == 'o') && a[1] >= '0' && a[1] < '0' + DRIVES && a[2] == '=') {
         Disk &d = hps.disk[a[1] - '0'];
         if(a[0] == 'o') { d.save = a + 3; continue; }
         FILE *fp = fopen(a + 3, "rb");
         if(!fp) { perror(a + 3); return 1; }
         fseek(fp, 0, SEEK_END); d.data.resize(ftell(fp)); fseek(fp, 0, SEEK_SET);
         if(fread(d.data.data(), 1, d.data.size(), fp) != d.data.size()) { perror(a + 3); return 1; }
         fclose(fp);
      }
      else if(a[0] == 'j' && sscanf(a + 1, "%d:%x", &f, &k) == 2) pads.push_back({f, (unsigned)k});
      else if(!strncmp(a, "t=", 2) && sscanf(a + 2, "%d:%n", &f, &n) == 1) {
         for(const char *c = a + 2 + n; *c; c++, f += TYPE_STEP_FRAMES) {
            int code = ps2_of(*c);
            if(!code) { fprintf(stderr, "can't type '%c'\n", *c); return 1; }
            keys.push_back({f, code, true});
            keys.push_back({f + TYPE_HOLD_FRAMES, code, false});
         }
      }
      else if(sscanf(a, "%d:%x", &f, &k) == 2) {
         int code = (k >> 8) == EXT_PREFIX ? PS2_EXT | (k & 0xFF) : k & 0xFF;
         keys.push_back({f, code, true});
         keys.push_back({f + KEY_HOLD_FRAMES, code, false});
      }
   }
   hps.latency = CLK_HZ / 1000000 * lat_us;

   Vsim_top *top = new Vsim_top;
   std::vector<unsigned char> fb(MAX_W * MAX_H * 3);

   int x = 0, y = 0, w = 0, h = 0, frame = 0;
   bool old_vs = false, old_de = false;
   long cycle = 0;

   top->RESET   = 1;
   top->ps2_key = 0;
   top->joystick = 0;

   auto tick = [&]() {
      hps.step(top);
      top->CLK_50M = 0; top->eval();
      top->CLK_50M = 1; top->eval();
      top->img_mounted = 0;
      cycle++;
   };

   while(frame < frames && !Verilated::gotFinish()) {
      tick();
      if(cycle == RESET_CYCLES) {
         top->RESET = 0;
         // mount the images, one drive per cycle as the HPS does
         for(int i = 0; i < DRIVES; i++) if(!hps.disk[i].data.empty()) {
            top->img_size    = hps.disk[i].data.size();
            top->img_mounted = 1 << i;
            tick();
         }
      }

      if(!top->CE_PIXEL) continue;

      if(top->VGA_DE) {
         if(x < MAX_W && y < MAX_H) {
            unsigned char *p = &fb[(y * MAX_W + x) * 3];
            p[0] = top->VGA_R; p[1] = top->VGA_G; p[2] = top->VGA_B;
         }
         x++;
      }
      else if(old_de) {
         if(x > w) w = x;
         x = 0;
         y++;
      }
      old_de = top->VGA_DE;

      if(top->VGA_VS && !old_vs) {
         if(y > h) h = y;
         if(frame % every == every - 1 && w && h) {
            char name[64];
            snprintf(name, sizeof name, "frame%04d.ppm", frame);
            FILE *f = fopen(name, "wb");
            fprintf(f, "P6\n%d %d\n255\n", w, h);
            for(int r = 0; r < h; r++) fwrite(&fb[r * MAX_W * 3], 3, w, f);
            fclose(f);
            printf("%s %dx%d sd reads %ld writes %ld\n", name, w, h, hps.reads, hps.writes);
            fflush(stdout);
         }
         frame++;
         for(const KeyEvent &e : keys) if(e.frame == frame) {
            top->ps2_key = ((top->ps2_key ^ PS2_TOGGLE) & PS2_TOGGLE) |
                           (e.pressed ? PS2_PRESSED : 0) | e.code;
            // one event per clk_sys edge at most: let this one be seen
            tick(); tick();
         }
         for(const PadEvent &e : pads) if(e.frame == frame) top->joystick = e.buttons;
         x = y = 0;
      }
      old_vs = top->VGA_VS;
   }

   for(int i = 0; i < DRIVES; i++) if(!hps.disk[i].save.empty()) {
      FILE *fp = fopen(hps.disk[i].save.c_str(), "wb");
      fwrite(hps.disk[i].data.data(), 1, hps.disk[i].data.size(), fp);
      fclose(fp);
   }
   printf("sd reads %ld writes %ld\n", hps.reads, hps.writes);

   delete top;
   return 0;
}
