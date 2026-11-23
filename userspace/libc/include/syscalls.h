
#include "stdint.h"

int syscall(uint32_t syscall_number, uint32_t arg1, uint32_t arg2, uint32_t arg3);

void exit(int code);

#define SYS_READ  0
#define SYS_WRITE 1
#define SYS_OPEN 2
#define SYS_CLOSE 3
#define SYS_LSEEK 8

#define SYS_MAP_FB 42
#define STD_IN_FILE_NO 0
#define STD_OUT_FILE_NO 1
#define SYS_EXIT 40
#define SYS_SLEEP 13
#define SYS_BRK 45

#define SYS_EXECVE 11
#define SYS_GET_PROC_UPTIME 12


