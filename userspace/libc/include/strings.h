//
// Created by cade on 6/15/26.
//

#ifndef C_OS_STRINGS_H
#define C_OS_STRINGS_H

#include "stdint.h"

void *memcpy (void *dest, const void *src, size_t n);
uint32_t parse_octal(const char *s, size_t n);
int strcmp(const char *s1, const char *s2);
void *memset(void *dest, int val, size_t count);
size_t strlen(const char *str);
char * strdup (const char *s);
char *strrchr(const char *str, int c);
int strcasecmp(const char *s1, const char *s2);
int strncasecmp(const char *s1, const char *s2, size_t n);
int isspace(int c);
void *memmove(void *dest, const void *src, size_t n);
int toupper(int c);
int tolower(int c);
char *strstr(const char *haystack, const char *needle);
int strncmp(const char *s1, const char *s2, size_t n);
char *strncpy(char *dest, const char *src, size_t n);

#endif //C_OS_STRINGS_H
