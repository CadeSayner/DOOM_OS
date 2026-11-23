
#ifndef STD_LIB_H
#define STD_LIB_H

#include "stdint.h"
#include "stdarg.h"

void* malloc(size_t size);
void free(void* addr);
void exit(int code);
int atoi(const char *str);
double atof(const char *str);

int vsnprintf(char *buf, size_t size, const char *format, va_list args);
int snprintf(char *buf, size_t size, const char *format, ...);
#endif //STD_LIB_H