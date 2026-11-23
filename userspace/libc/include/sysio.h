//
// Created by cade on 6/15/26.
//

#ifndef C_OS_IO_SYSCALLS_H
#define C_OS_IO_SYSCALLS_H

#include "stdint.h"

int open(const char *pathname, int flags, ...);
ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
int close(int fd);
off_t lseek(int fd, off_t offset, int whence);

#define SYS_READ  0
#define SYS_WRITE 1
#define SYS_OPEN 2
#define SYS_CLOSE 3
#define SYS_LSEEK 8
#define STD_IN_FILE_NO 0
#define STD_OUT_FILE_NO 1

#endif //C_OS_IO_SYSCALLS_H
