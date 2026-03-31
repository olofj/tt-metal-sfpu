#!/usr/bin/env python3
"""Read program counter from Tensix RISC-V cores using tt-exalens.

Usage (from ~/.tenstorrent-venv):
  python read_pc.py                    # Read all RISCs on core (1,2)
  python read_pc.py --core 2,3         # Specific core
  python read_pc.py --all              # First row of cores
  python read_pc.py --elf kernel.elf   # Resolve addresses to symbols
"""
import argparse
import time


def load_symbols(elf_path):
    """Load function symbols from an ELF file."""
    symbols = []
    try:
        from elftools.elf.elffile import ELFFile
        with open(elf_path, 'rb') as f:
            elf = ELFFile(f)
            symtab = elf.get_section_by_name('.symtab')
            if symtab:
                for sym in symtab.iter_symbols():
                    if sym['st_size'] > 0:
                        symbols.append((sym['st_value'], sym['st_size'], sym.name))
                symbols.sort()
        print(f"Loaded {len(symbols)} symbols from {elf_path}")
    except Exception as e:
        print(f"Warning: could not load symbols: {e}")
    return symbols


def resolve(symbols, addr):
    if addr is None:
        return None
    for base, size, name in symbols:
        if base <= addr < base + size:
            return f"{name}+0x{addr - base:x}"
    return None


def dump_core(device, coords, symbols, halt=False):
    """Read PCs from all RISCs on a core."""
    from ttexalens.coordinate import OnChipCoordinate

    print(f"\n{'='*60}")
    print(f"Core ({coords})")
    print(f"{'='*60}")

    loc = OnChipCoordinate.create(coords, device)
    block = device.get_block(loc)

    # Read soft reset
    try:
        rst = device.noc_read32(loc, 0xFFB121B0)
        print(f"  soft_reset_0: 0x{rst:08X}", end="")
        if rst == 0:
            print("  (all running)")
        else:
            parts = []
            if rst & 0x00800: parts.append("BRISC_RST")
            if rst & 0x07000: parts.append("TRISCS_RST")
            if rst & 0x40000: parts.append("NCRISC_RST")
            print(f"  ({', '.join(parts)})" if parts else f"  (0x{rst:x})")
    except Exception as e:
        print(f"  soft_reset: Error: {e}")

    for risc_name in block.risc_names:
        dbg = block.get_risc_debug(risc_name)

        # Optionally halt
        if halt:
            try:
                dbg.halt()
            except Exception:
                pass

        # Read PC
        try:
            pc = dbg.read_gpr(32)
            pc_str = f"0x{pc:08X}"
            sym = resolve(symbols, pc) if symbols else None
            sym_str = f"  ({sym})" if sym else ""
        except Exception as e:
            pc = None
            pc_str = f"Error: {e}"
            sym_str = ""

        # Read status
        try:
            status = dbg.read_status()
            halted_str = " HALTED" if status.is_halted else ""
        except Exception:
            halted_str = ""

        print(f"  {risc_name:8s}: PC={pc_str}{sym_str}{halted_str}")

        # Read key GPRs
        if pc is not None:
            try:
                ra = dbg.read_gpr(1)
                sp = dbg.read_gpr(2)
                gp = dbg.read_gpr(3)
                ra_sym = resolve(symbols, ra) if symbols else None
                ra_str = f"  ({ra_sym})" if ra_sym else ""
                print(f"           ra=0x{ra:08X}{ra_str}  sp=0x{sp:08X}  gp=0x{gp:08X}")
            except Exception:
                pass

        # Resume if we halted
        if halt:
            try:
                dbg.cont()
            except Exception:
                pass


def main():
    parser = argparse.ArgumentParser(description="Read PC from Tensix RISC-V cores")
    parser.add_argument("--core", default="1,2", help="Core X,Y (default: 1,2)")
    parser.add_argument("--all", action="store_true", help="Read first row of Tensix cores")
    parser.add_argument("--elf", help="Kernel ELF for symbol resolution")
    parser.add_argument("--halt", action="store_true", help="Halt cores before reading (more accurate)")
    args = parser.parse_args()

    from ttexalens.tt_exalens_init import init_ttexalens
    ctx = init_ttexalens(use_noc1=False)
    device = ctx.devices[0]
    print("Connected to BH via tt-exalens")

    symbols = load_symbols(args.elf) if args.elf else []

    if args.all:
        core_list = [f"{x},2" for x in range(1, 8)]
    else:
        core_list = [args.core]

    for coords in core_list:
        try:
            dump_core(device, coords, symbols, halt=args.halt)
        except Exception as e:
            print(f"  Core ({coords}): Error: {e}")
            import traceback
            traceback.print_exc()


if __name__ == "__main__":
    main()
