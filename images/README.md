# M65832 Boot Images

Build artifacts for booting Linux on the M65832 emulator and hardware.

## Files

| File | Description | Built From |
|------|-------------|------------|
| `boot.img` | Bootable disk image (boot header + kernel + rootfs) | `scripts/mkbootimg` |
| `vmlinux.bin` | Flat kernel binary, loaded at physical 0x00100000 | `llvm-objcopy -O binary` from `linux-m65832/vmlinux` |
| `rootfs.img` | ext2 root filesystem with minimal `/init` | `mkfs.ext2` + `debugfs` |

## Disk Layout (boot.img)

```
Sector 0        Boot header (magic "M65B", kernel location/size/load addr)
Sectors 1-2047  Reserved
Sector 2048+    Kernel flat binary (vmlinux.bin)
Sector 16384+   Root filesystem (rootfs.img, ext2)
```

## How to Rebuild

```bash
# 1. Build the Linux kernel
cd ../linux-m65832
./scripts/build-m65832.sh config
./scripts/build-m65832.sh build

# 2. Create flat binary
../m65832/bin/llvm-objcopy -O binary vmlinux ../m65832/images/vmlinux.bin

# 3. Create bootable disk image
../m65832/scripts/mkbootimg \
    --kernel ../m65832/images/vmlinux.bin \
    --rootfs ../m65832/images/rootfs.img \
    -o ../m65832/images/boot.img
```

## How to Boot

```bash
# Boot in emulator (boot ROM loads kernel from disk automatically)
m65832emu --disk images/boot.img
```

## Boot Flow

1. CPU resets, executes **boot ROM** at `0xFFFF0000`
2. Boot ROM reads sector 0, parses boot header
3. Boot ROM DMA-loads kernel from sector 2048 to RAM at `0x00100000`
4. Boot ROM jumps to `0x00100000` (kernel `_start` in `head.S`)
5. `head.S` clears BSS, builds page tables, enables MMU
6. `head.S` jumps to virtual `start_kernel` at `0x80xxxxxx`
7. Kernel initializes, mounts rootfs from block device, runs `/init`
