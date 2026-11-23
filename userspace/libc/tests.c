#include "stdint.h"
#include "stdlib.h"
#include "strings.h"
#include "stdio.h"
#include "sysio.h"
#include "errno.h"

int main(void)
{
    char buf[64];
    char overlap[] = "abcdef";
    char *a, *b;
    FILE *wad;

    memset(buf, 'x', sizeof(buf));
    if (buf[63] != 'x') return 1;
    memmove(overlap + 1, overlap, 5);
    if (strcmp(overlap, "aabcde") != 0) return 2;
    if (snprintf(buf, sizeof(buf), "%s %04d %.2x", "test", -7, 5) != 12) return 3;
    if (strcmp(buf, "test -007 05") != 0) return 4;
    if (snprintf(buf, 4, "%s", "hello") != 5 || strcmp(buf, "hel") != 0) return 5;

    a = malloc(37);
    b = malloc(80);
    if (!a || !b || ((uintptr_t)a & 15) != 0) return 6;
    memset(a, 42, 37);
    free(a);
    if (malloc(32) != a || b[0] != 0) return 7;

    if (open("missing-file", 0) != -1 || errno != ENOENT) return 8;
    wad = fopen("doom1.wad", "rb");
    if (!wad || fread(buf, 1, 4, wad) != 4) return 9;
    if (strncmp(buf, "IWAD", 4) != 0) return 10;
    if (fseek(wad, 0, SEEK_END) != 0 || ftell(wad) <= 4) return 11;
    if (fclose(wad) != 0) return 12;

    if (printf("libc tests passed: %04d %s\n", 7, "ok") != 27) return 13;
    return 0;
}
