#ifndef MUTTR_CLI_BRIDGING_HEADER_H
#define MUTTR_CLI_BRIDGING_HEADER_H

#include <util.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <termios.h>
#include <unistd.h>

static inline int pty_getwinsize(int fd, struct winsize *ws) {
    return ioctl(fd, TIOCGWINSZ, ws);
}

static inline int pty_setwinsize(int fd, struct winsize *ws) {
    return ioctl(fd, TIOCSWINSZ, ws);
}

#endif
