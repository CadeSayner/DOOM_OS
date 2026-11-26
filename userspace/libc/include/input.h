#ifndef DOOM_OS_INPUT_H
#define DOOM_OS_INPUT_H

#include "stdint.h"

typedef struct {
    uint8_t scan_code;
    uint8_t ascii;
    uint8_t pressed;
    uint8_t shift;
    uint8_t extended;
} key_event_t;

#endif
