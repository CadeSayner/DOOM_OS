//
// Created by cade on 6/17/26.
//
#include "doomgeneric.h"
#include  "stdint.h"
#include "stddef.h"

// Doom key constants
#define KEY_ENTER       13
#define KEY_ESCAPE      27
#define KEY_LEFTARROW   0xac
#define KEY_RIGHTARROW  0xae
#define KEY_UPARROW     0xad
#define KEY_DOWNARROW   0xaf
#define KEY_USE         0xa2
#define KEY_FIRE        0xa3

extern ssize_t read(const int fd, void *buf, const size_t count);
extern void *map_linear_framebuffer();
extern void sleep(const uint32_t ms);
extern uint32_t sys_get_proc_uptime();


static uint32_t *os_framebuffer = NULL;

void DG_Init()
{
    os_framebuffer = (uint32_t *)map_linear_framebuffer();
}

void DG_DrawFrame()
{
    const int fb_width = 1280;
    const int fb_height = 720;

    for (int y = 0; y < fb_height; y++)
    {
        int src_y = y * DOOMGENERIC_RESY / fb_height;

        for (int x = 0; x < fb_width; x++)
        {
            int src_x = x * DOOMGENERIC_RESX / fb_width;

            os_framebuffer[y * fb_width + x] =
                DG_ScreenBuffer[src_y * DOOMGENERIC_RESX + src_x];
        }
    }
}

void DG_SleepMs(uint32_t ms)
{
    sleep(ms);
}

uint32_t DG_GetTicksMs()
{
    return sys_get_proc_uptime()*50;
}

int DG_GetKey(int* pressed, unsigned char* key)
{
    typedef struct {
        unsigned char key;
        uint32_t release_time;
        int active;
        int release_sent;
    } held_key_t;

    static held_key_t held[8];

    uint32_t now = DG_GetTicksMs();

    // First, emit delayed key-up events
    for (int i = 0; i < 8; i++) {
        if (held[i].active && !held[i].release_sent && now >= held[i].release_time) {
            held[i].release_sent = 1;
            held[i].active = 0;

            *pressed = 0;
            *key = held[i].key;
            return 1;
        }
    }

    // Then read a new input byte
    uint8_t input_char = 0;
    ssize_t bytes_read = read(0, &input_char, 1);

    if (bytes_read <= 0)
        return 0;

    unsigned char doom_key;

    switch (input_char)
    {
        case 27:
            doom_key = KEY_ESCAPE;
            break;
        case 13:
        case 10:
            doom_key = KEY_ENTER;
            break;
        case 'u': case 'U':
        case 'e': case 'E':
        case ' ':
            doom_key = KEY_USE;
            break;

        case 'w': case 'W':
            doom_key = KEY_UPARROW;
            break;
        case 's': case 'S':
            doom_key = KEY_DOWNARROW;
            break;
        case 'a': case 'A':
            doom_key = KEY_LEFTARROW;
            break;
        case 'd': case 'D':
            doom_key = KEY_RIGHTARROW;
            break;

        case 'f': case 'F':
        case 'j': case 'J':
            doom_key = KEY_FIRE;
            break;

        default:
            doom_key = input_char;
            break;
    }

    // Store/restart fake hold timer
    int slot = -1;

    for (int i = 0; i < 8; i++) {
        if (held[i].active && held[i].key == doom_key) {
            slot = i;
            break;
        }
    }

    if (slot == -1) {
        for (int i = 0; i < 8; i++) {
            if (!held[i].active) {
                slot = i;
                break;
            }
        }
    }

    if (slot != -1) {
        held[slot].key = doom_key;
        held[slot].release_time = now + 120; // key held for 120ms
        held[slot].active = 1;
        held[slot].release_sent = 0;
    }

    *pressed = 1;
    *key = doom_key;
    return 1;
}

void DG_SetWindowTitle(const char *title)
{
    // Bare-metal operating systems don't have desktop window borders.
    // Leave this completely blank.
}


// 64-bit integer division tracking hook injected by GCC for 32-bit architectures
long long __divdi3(long long num, long long den) {
    long long quot = 0, qbit = 1;
    int sign = 1;
    if (num < 0) { sign = -sign; num = -num; }
    if (den < 0) { sign = -sign; den = -den; }
    if (den == 0) return 0; // Avoid division by zero crash
    while (den < num && !(den & (1ULL << 63))) { den <<= 1; qbit <<= 1; }
    while (qbit) {
        if (num >= den) { num -= den; quot |= qbit; }
        den >>= 1; qbit >>= 1;
    }
    return sign < 0 ? -quot : quot;
}

int main(int argc, char **argv)
{
    doomgeneric_Create(argc, argv);

    while (1)
    {
        doomgeneric_Tick();
    }

    return 0;
}