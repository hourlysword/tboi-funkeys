// SPDX-License-Identifier: MIT
/* struct input_event as the FunKey's kernel writes it, for everything built with cmake/funkey.cmake (-isystem).
 *
 * The FunKey SDK pairs musl 1.2.1, whose time_t is 64-bit, with Linux 4.14's headers, which declare the event's time as
 * a struct timeval: 16 bytes there, so struct input_event comes out at 24 bytes. A 32-bit ARM kernel reads and writes
 * 16-byte events (two 32-bit time fields), whatever the C library's time_t: a program built with the SDK's header
 * misreads every event from /dev/input. (Headers from Linux 4.16 on declare the 32-bit fields when the C library
 * defines __USE_TIME_BITS64, as musl does.) SDL2 reads keys this way, through its evdev input.
 *
 * From my other FunKey S projects, where every button was dead until this was found. */
#ifndef TFK_FUNKEY_LINUX_INPUT_H
#define TFK_FUNKEY_LINUX_INPUT_H

#define input_event tfk_linux414_input_event
#include_next <linux/input.h>
#undef input_event

struct input_event {
    __kernel_ulong_t __sec;
    __kernel_ulong_t __usec;
    __u16 type;
    __u16 code;
    __s32 value;
};
#define input_event_sec __sec
#define input_event_usec __usec

#ifdef __cplusplus
static_assert(sizeof(struct input_event) == 16, "struct input_event must match the 32-bit ARM kernel's");
#else
_Static_assert(sizeof(struct input_event) == 16, "struct input_event must match the 32-bit ARM kernel's");
#endif

#endif
