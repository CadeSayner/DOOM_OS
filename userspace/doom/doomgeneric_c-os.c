//
// Created by cade on 6/17/26.
//
#include "doomgeneric.h"
#include "doomkeys.h"
#include "errno.h"
#include "input.h"
#include "stdio.h"
#include "sysio.h"

extern void *map_linear_framebuffer();
extern void sleep(const uint32_t ms);
extern uint32_t sys_get_proc_uptime();

static uint32_t *os_framebuffer = NULL;
static int input_fd = -1;

static void input_error(const char *operation, int error)
{
    fprintf(stderr, "Doom input %s failed: %d\n", operation, error);
    exit(error != 0 ? error : 1);
}

void DG_Init()
{
    os_framebuffer = (uint32_t *)map_linear_framebuffer();
    input_fd = open("/dev/input", O_RDONLY | O_NONBLOCK);
    if (input_fd < 0)
        input_error("open", errno);
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
    key_event_t event;

    for (;;)
    {
        ssize_t bytes_read = read(input_fd, &event, sizeof(event));
        if (bytes_read == 0)
            return 0;
        if (bytes_read < 0)
            input_error("read", errno);
        if (bytes_read != sizeof(event))
            input_error("short read", 0);

        unsigned char doom_key = 0;
        if (event.extended)
        {
            switch (event.scan_code)
            {
                case 0x48: doom_key = KEY_UPARROW; break;
                case 0x50: doom_key = KEY_DOWNARROW; break;
                case 0x4b: doom_key = KEY_LEFTARROW; break;
                case 0x4d: doom_key = KEY_RIGHTARROW; break;
                case 0x1c: doom_key = KEY_ENTER; break;
            }
        }
        else
        {
            switch (event.scan_code)
            {
                case 0x2a: case 0x36: doom_key = KEY_RSHIFT; break;
                case 0x0e: doom_key = KEY_BACKSPACE; break;
                case 0x1c: doom_key = KEY_ENTER; break;
                default:
                    if (event.scan_code >= 0x3b && event.scan_code <= 0x44)
                        doom_key = 0x80 + event.scan_code;
                    else if (event.scan_code == 0x57 || event.scan_code == 0x58)
                        doom_key = 0x80 + event.scan_code;
                    else
                        doom_key = event.ascii;
                    break;
            }
        }

        switch (doom_key)
        {
            case 'u': case 'e': case ' ': doom_key = KEY_USE; break;
            case 'w': doom_key = KEY_UPARROW; break;
            case 's': doom_key = KEY_DOWNARROW; break;
            case 'a': doom_key = KEY_LEFTARROW; break;
            case 'd': doom_key = KEY_RIGHTARROW; break;
            case 'f': case 'j': doom_key = KEY_FIRE; break;
        }

        if (doom_key != 0)
        {
            *pressed = event.pressed != 0;
            *key = doom_key;
            return 1;
        }
    }
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