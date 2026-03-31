# Debugging Kernel Hangs on Blackhole Silicon

Hard-won lessons from debugging an LLVM-compiled SFPU kernel hang on BH.

## TL;DR

What looked like a dispatch/loader bug turned out to be the LLVM-compiled kernel code itself hanging during execution. The investigation took many wrong turns because:
1. PC reads from compute cores showed firmware wait-for-GO (misleading — a cascading stall from the host CQ filling up)
2. The `.data` section difference was a red herring (proven by patching GCC ELFs with `.data`)
3. The fast dispatch relay appeared stuck, but it was actually waiting for the kernel to complete

**Root cause**: The LLVM-compiled `math_main` (SFPU gelu code) hangs the TRISC1 core. Slow dispatch confirmed the binary write to L1 succeeds instantly — the hang is during kernel execution.

## Debugging Toolkit

### 1. tt-exalens for reading PCs

```bash
# Install in separate venv
pip install tt-exalens  # in ~/.tenstorrent-venv

# Read PCs from a compute core
python3 read_pc.py --core "1,2" --halt

# Scan all compute cores
python3 read_pc.py --all --halt
```

**Pitfall**: tt-exalens opens its own device connection. Run it from a SEPARATE venv while the test is still running (it will wait for the device lock). Don't run it after the test exits — device close resets all cores.

**Pitfall**: PC reads can be misleading. When the host CQ is full (waiting for kernel completion), the dispatch relay stalls, which prevents GO signals from being delivered to compute cores. All cores then show firmware wait-for-GO even though the actual bug is in a single core's kernel execution.

### 2. Finding the dispatch core

On BH with `DispatchCoreAxis::COL` (fabric disabled), dispatch cores are at the last logical column:
```
Dispatch core coordinates defined in: tt_metal/core_descriptors/blackhole_140_arch.yaml
  dispatch_cores: [[-1, 0], [-1, 1], ...]  # -1 = last column
```

With harvesting mask 0xC0 (cols 6,7 harvested), the last logical column is 11. Scan `(11,0)` and `(11,1)`:
- `(11,0)` = prefetcher (cq_prefetch kernel, BRISC)
- `(11,1)` = dispatcher (cq_dispatch kernel, BRISC) + dispatch subordinate (NCRISC)

### 3. Resolving runtime PCs to source code

Kernel binaries are loaded at runtime addresses different from their ELF link addresses:
```
runtime_addr = kernel_config_base + kernel_text_offset + (elf_addr - elf_text_start)
```

Use `addr2line` with the ELF:
```bash
riscv-tt-elf-addr2line -e kernel.elf -f -C 0xBF98
```

To find `kernel_config_base`, add logging in `dispatch.cpp` around line 2263:
```cpp
log_info(tt::LogDispatch, "kernel_config_base[{}] = 0x{:x}", i, dispatch_md.kernel_config_addrs[i].addr);
```

### 4. Slow dispatch as a diagnostic tool

```bash
export TT_METAL_SLOW_DISPATCH_MODE=1
```

Slow dispatch bypasses the dispatch relay entirely. The host writes kernel binaries directly via PCIe-to-NOC `write_core()`. If a hang persists with slow dispatch, the bug is in the **kernel code execution**, not the dispatch infrastructure.

Add progress logging in `tt_metal.cpp` `LaunchProgram()`:
```cpp
log_info(tt::LogMetal, "LaunchProgram: ConfigureDeviceWithProgram starting...");
detail::ConfigureDeviceWithProgram(device, program, force_slow_dispatch);
log_info(tt::LogMetal, "LaunchProgram: ConfigureDeviceWithProgram done");
```

If `ConfigureDeviceWithProgram` completes but the test hangs, the kernel launched successfully and is hanging during execution.

### 5. Binary patching to isolate the bug

**Isolate which TRISC hangs** (trisc0=unpack, trisc1=math, trisc2=pack):
```python
# Copy GCC ELF over suspected LLVM ELF in the cache
cp gcc_cache/trisc1/trisc1.elf llvm_cache/trisc1/trisc1.elf
rm -f llvm_cache/trisc1/trisc1.elf.xip.elf  # force regeneration
```

**Insert infinite loop at kernel entry**:
```python
# j . = 0x0000006F at .text offset 0 (first instruction of _start)
struct.pack_into('<I', data, text_file_offset, 0x0000006F)
```

If the core's PC matches the `j .` address, execution reached that point. If it doesn't, the hang is earlier (or the kernel never starts).

**Replace .text content while keeping ELF structure**:
```python
# Take LLVM ELF, overwrite .text with GCC code + NOP padding
data[text_off:text_off+gcc_size] = gcc_text
for j in range(gcc_size, llvm_size, 4):
    struct.pack_into('<I', data, text_off + j, 0x13)  # NOP
```

This lets you test whether the ELF structure/metadata matters vs the actual code content.

### 6. Binary search for the failing code region

Use subprocess with `timeout` and **proper synchronization** (call `ttnn.to_torch()` to force a wait):

```python
r = subprocess.run(["bash", "-c",
    "... timeout 20 python -c \""
    "import ttnn, torch\n"
    "d = ttnn.open_device(device_id=0)\n"
    "x = ttnn.from_torch(torch.randn(1,1,32,32), ...)\n"
    "r = ttnn.gelu(x)\n"
    "o = ttnn.to_torch(r)\n"  # THIS FORCES SYNCHRONIZATION - without it, "OK" prints before hang
    "print('PASS')\n"
    "ttnn.close_device(d)\n"
    "\""], ...)
ok = "PASS" in r.stdout
```

**Critical**: Without `to_torch()`, the test prints "PASS" before the kernel finishes because `ttnn.gelu()` is asynchronous. This caused hours of misleading binary search results.

## Key Lessons

### Cascading stalls are misleading

In fast dispatch, when a kernel hangs on one core:
1. That core never signals completion
2. The host CQ fills up waiting for completion
3. The dispatch relay can't process new commands (CQ is full)
4. No new GO signals are sent to any core
5. ALL cores appear to be in firmware wait-for-GO

This makes it look like a dispatch infrastructure bug when it's actually a kernel bug.

### The `.data` section was a red herring

The LLVM kernel had a non-empty `.data` section (24 bytes of MMIO pointers). Initial hypothesis: the dispatch can't handle non-empty `.data`. Proven wrong by:
1. Dispatch kernels (cq_dispatch, cq_prefetch) ALSO have `.data` sections and work fine
2. Patching GCC ELFs to have `.data` sections → works
3. Patching GCC ELFs to match LLVM binary size + `.data` → works
4. The `.data` section is correctly handled by XIPify and the memory loader

### ELF cache invalidation

The kernel cache uses `build_key_` (env hash) + kernel-specific hash. Changing compile flags in the HAL doesn't always change the build key. To force a clean rebuild:
```bash
rm -rf ~/.cache/tt-metal-cache/BUILD_KEY_DIR/
```

### Test methodology matters

- Always use `tt-smi -r` between test runs (hardware reset)
- Wait 2 seconds after reset before running
- Delete `.xip.elf` files when patching ELFs (they're regenerated automatically)
- Use the tenstorrent venv (`~/.tenstorrent-venv`) for tt-exalens, and the project venv (`.venv`) for tt-metal

## Dispatch Architecture Reference

```
Host Process
  │
  ├─ Fast Dispatch (default):
  │   ├─ Writes commands to hugepage (host memory)
  │   ├─ Prefetcher (core 11,0 BRISC) reads from hugepage/DRAM
  │   ├─ Dispatcher (core 11,1 BRISC) writes to compute cores via NOC
  │   └─ GO signal delivered by dispatcher
  │
  └─ Slow Dispatch (TT_METAL_SLOW_DISPATCH_MODE=1):
      ├─ Host writes binaries directly via write_core() (PCIe→NOC)
      ├─ Host writes launch_msg and GO signal directly
      └─ Host polls for completion

Compute Core (e.g., 1,2):
  BRISC  (0x38C0-0x4B5C): firmware, reads GO signal, jumps to kernel
  NCRISC (0x5xxx):         firmware, data movement
  TRISC0 (0x64xx):         firmware → unpack kernel
  TRISC1 (0x6Exx-0x70xx):  firmware → math/SFPU kernel  ← THIS IS WHERE GELU RUNS
  TRISC2 (0x78xx-0x7Axx):  firmware → pack kernel

Config Buffer (0x9DE0+):
  Ring buffer for kernel binaries, CB configs, RTAs, semaphores
  kernel_text_offset[i] = offset within buffer for processor i's binary
```
