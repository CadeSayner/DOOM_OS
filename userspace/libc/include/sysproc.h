//
// Created by cade on 6/17/26.
//

#ifndef C_OS_SYS_PROC_H
#define C_OS_SYS_PROC_H
#include "stdint.h"

uint32_t sys_get_proc_uptime();
void sleep(uint32_t ms);
int execve(const char *path, char *const argv[], char *const envp[]);

#endif //C_OS_SYS_PROC_H
