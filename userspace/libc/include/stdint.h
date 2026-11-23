#ifndef DOOM_OS_STDINT_H
#define DOOM_OS_STDINT_H

#include "stddef.h"

typedef signed char int8_t;
typedef unsigned char uint8_t;

typedef signed short int16_t;
typedef unsigned short uint16_t;

typedef signed long int int32_t;
typedef unsigned long int uint32_t;

typedef long ssize_t;

typedef long unsigned int addr_t;

typedef signed long long int64_t;
typedef unsigned long long uint64_t;
typedef int intptr_t;
typedef unsigned int uintptr_t;
typedef long off_t;

typedef uint8_t bool;
#define true 1
#define false 0

#endif
