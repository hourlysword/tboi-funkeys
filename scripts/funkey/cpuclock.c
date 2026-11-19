// SPDX-License-Identifier: MIT
// cpuclock: reads or sets the CPU clock of the FunKey S (Allwinner V3s). The OPK's launcher runs the game faster with
// it and puts the clock back afterwards. From my other FunKey S projects.
//
//   cpuclock          prints the current CPU clock in MHz
//   cpuclock <MHz>    sets the highest multiple of 48 MHz up to <MHz>, from 480 to 1296 MHz, the highest operating
//                     point of the V3s in the FunKey kernel (at 1.2 V, like the default 1008 MHz)
//
// FunKey-OS has no cpufreq driver: the clock is set through the clock registers (/dev/mem, so root only; the launchers
// run as root). PLL_CPUX = 24 MHz * N * K / M, with K and M as U-Boot sets them for each clock (pll_factors). Like the
// kernel's clock driver, the CPU runs from the 24 MHz oscillator while the PLL relocks, and the old setting is restored
// if it doesn't lock. The voltage is not changed.
//
// make-opk.sh builds it: $FUNKEY_SDK/bin/arm-funkey-linux-musleabihf-gcc -O2 -o cpuclock cpuclock.c

#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

#define MHZ_STEP 48
#define MHZ_MIN 480
#define MHZ_MAX 1296

#define CCU_BASE 0x01c20000
#define PLL_CPUX (0x000 / 4)
#define CPU_AXI_CFG (0x050 / 4)
#define PLL_ENABLE (1u << 31)
#define PLL_LOCK (1u << 28)
#define PLL_K2_M1 (1u << 4)
#define PLL_K4_M2 ((3u << 4) | 1u)
#define CPU_SRC_MASK (3u << 16)
#define CPU_SRC_OSC24M (1u << 16)
#define CPU_SRC_PLL (2u << 16)

static void spin(uint32_t count) {
    volatile uint32_t n = count;
    while (n--) {
    }
}

static unsigned pll_mhz(uint32_t pll) {
    const uint32_t n = ((pll >> 8) & 0x1f) + 1;
    const uint32_t k = ((pll >> 4) & 3) + 1;
    const uint32_t m = (pll & 3) + 1;
    const uint32_t p = 1u << ((pll >> 16) & 3);
    return 24 * n * k / (m * p);
}

static unsigned cpu_mhz(volatile uint32_t* ccu) {
    return ((ccu[CPU_AXI_CFG] & CPU_SRC_MASK) >= CPU_SRC_PLL) ? pll_mhz(ccu[PLL_CPUX]) : 24;
}

// The lock bit drops while the PLL settles: give it some time before polling.
static int wait_lock(volatile uint32_t* ccu) {
    spin(3000);
    for (int i = 0; i < 1000000; i++) {
        if (ccu[PLL_CPUX] & PLL_LOCK) {
            return 1;
        }
    }
    return 0;
}

// N, K and M for mhz, as U-Boot chooses them (clock_set_pll1): the PLL itself runs at 24 MHz * N * K, which has to
// stay in its range. With K = 4 and M = 2 at 1296 MHz it would run at 2592 MHz, and the CPU got slower instead (about
// 780 MHz measured).
static uint32_t pll_factors(int mhz) {
    if (mhz > 1152) {
        return ((uint32_t)(mhz / 48 - 1) << 8) | PLL_K2_M1;
    }
    if (mhz > 768) {
        return ((uint32_t)(mhz / 48 - 1) << 8) | PLL_K4_M2;
    }
    return (uint32_t)(mhz / 24 - 1) << 8;
}

static int set_cpu_mhz(volatile uint32_t* ccu, int mhz) {
    const uint32_t axi = ccu[CPU_AXI_CFG];
    const uint32_t old = ccu[PLL_CPUX];
    mhz = mhz < MHZ_MIN ? MHZ_MIN : mhz > MHZ_MAX ? MHZ_MAX : mhz;
    mhz = mhz / MHZ_STEP * MHZ_STEP;

    ccu[CPU_AXI_CFG] = (axi & ~CPU_SRC_MASK) | CPU_SRC_OSC24M;
    spin(1000);
    ccu[PLL_CPUX] = PLL_ENABLE | pll_factors(mhz);
    const int locked = wait_lock(ccu);
    if (!locked) {
        ccu[PLL_CPUX] = old;
        wait_lock(ccu);
    }
    ccu[CPU_AXI_CFG] = (axi & ~CPU_SRC_MASK) | CPU_SRC_PLL;
    spin(1000);
    return locked;
}

int main(int argc, char* argv[]) {
    if (argc > 2 || (argc == 2 && atoi(argv[1]) <= 0)) {
        fprintf(stderr, "usage: %s [MHz, %d-%d]\n", argv[0], MHZ_MIN, MHZ_MAX);
        return 1;
    }
    const int fd = open("/dev/mem", O_RDWR | O_SYNC | O_CLOEXEC);
    void* map = fd < 0 ? MAP_FAILED : mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, CCU_BASE);
    if (map == MAP_FAILED) {
        perror("cpuclock: the clock registers (/dev/mem)");
        return 1;
    }
    close(fd);
    volatile uint32_t* ccu = (volatile uint32_t*)map;
    // U-Boot leaves the CPU running from PLL_CPUX, enabled and locked. Anything else is not a V3s's clock unit (the
    // test VM has its boot flash at this address): nothing is read from it as a clock, or written to it.
    const uint32_t pll = ccu[PLL_CPUX];
    if (!(pll & PLL_ENABLE) || !(pll & PLL_LOCK) || (ccu[CPU_AXI_CFG] & CPU_SRC_MASK) < CPU_SRC_PLL) {
        fprintf(stderr, "cpuclock: no Allwinner V3s clock unit here (PLL_CPUX 0x%08x): the clock is left alone\n",
                (unsigned)pll);
        return 1;
    }
    if (argc == 1) {
        printf("%u\n", cpu_mhz(ccu));
        return 0;
    }
    if (!set_cpu_mhz(ccu, atoi(argv[1]))) {
        fprintf(stderr, "cpuclock: the PLL did not lock, the CPU clock stays at %u MHz\n", cpu_mhz(ccu));
        return 1;
    }
    printf("CPU clock %u MHz\n", cpu_mhz(ccu));
    return 0;
}
