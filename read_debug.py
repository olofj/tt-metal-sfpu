#!/usr/bin/env python3
"""Read debug breadcrumbs from trisc cores while kernel is hung."""
import sys
sys.path.insert(0, '/work/llvm/tt-metal-sfpu')

# Try to use UMD/pyluwen to read from the device
try:
    from pyluwen import PciChip
    chip = PciChip(pci_interface=0)

    # Read from core (1,2) at address 0xFFB00FF0
    # The debug breadcrumb was written there by the kernel
    for core_x, core_y in [(1,2), (2,2), (3,2)]:
        try:
            data = chip.noc_read(core_x, core_y, 0xFFB00FF0, 4)
            val = int.from_bytes(data, 'little')
            stage = (val >> 16) & 0xFF
            trisc = val & 0xFF
            print(f"Core ({core_x},{core_y}): 0x{val:08X} -> stage={stage}, trisc={trisc}")
        except Exception as e:
            print(f"Core ({core_x},{core_y}): Error: {e}")
except ImportError:
    print("pyluwen not available, trying ttexalens...")
    try:
        from ttexalens.tt_exalens_init import init_ttexalens
        from ttexalens.coordinate import OnChipCoordinate
        from ttexalens.tt_exalens_lib import read_words_from_device

        context = init_ttexalens(use_noc1=False)
        device = context.devices[0]

        for coords in ["1,2", "2,2", "3,2"]:
            location = OnChipCoordinate.create(coords, device)
            words = read_words_from_device(location, 0xFFB00FF0, word_count=1)
            val = words[0]
            stage = (val >> 16) & 0xFF
            trisc = val & 0xFF
            print(f"Core {coords}: 0x{val:08X} -> stage={stage}, trisc={trisc}")
    except Exception as e:
        print(f"ttexalens error: {e}")
        print("Trying raw UMD...")
        try:
            import pyluwen
            print(dir(pyluwen))
        except:
            print("No debug tools available. Install pyluwen or ttexalens.")
