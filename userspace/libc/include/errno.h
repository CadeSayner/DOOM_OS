//
// Created by cade on 6/15/26.
//

#ifndef C_OS_ERRNO_H
#define C_OS_ERRNO_H

extern int errno;

#define ENOENT  2
#define ESRCH   3
#define EBADF   9
#define ENOMEM 12
#define EFAULT 14
#define EISDIR 21
#define EINVAL 22
#define EMFILE 24
#define ESPIPE 29
#define ENOSYS 38

#endif //C_OS_ERRNO_H
