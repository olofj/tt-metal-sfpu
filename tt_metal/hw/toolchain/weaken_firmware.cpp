// SPDX-FileCopyrightText: © 2024 Tenstorrent Inc.
//
// SPDX-License-Identifier: Apache-2.0

// Standalone firmware symbol weakener.
//
// Processes a firmware ELF binary to weaken/localize symbols so that it can be
// used as a "library" when JIT-linking user kernels.  Symbols matching the
// strong prefixes (default: "__fw_export_*" and "__global_pointer$") remain
// at full strength; all other global function symbols are localized and data
// symbols are weakened.
//
// This is the Bazel-side equivalent of JitBuildState::weaken() in
// tt_metal/jit_build/build.cpp (lines 583-597).
//
// Links against tt_elffile.cpp compiled with -DELF_STANDALONE
// (provides stub TT_THROW/log_debug without the full tt-metal infrastructure).

#include "tt_metal/llrt/tt_elffile.hpp"

#include <cstdio>
#include <cstring>
#include <string_view>
#include <vector>

static void usage(const char* prog) {
    fprintf(stderr, "Usage: %s [--objectify] <input.elf> <output.elf>\n", prog);
}

int main(int argc, char* argv[]) {
    bool objectify = false;
    std::vector<const char*> positional;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--objectify") == 0) {
            objectify = true;
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(argv[0]);
            return 0;
        } else {
            positional.push_back(argv[i]);
        }
    }

    if (positional.size() != 2) {
        usage(argv[0]);
        return 1;
    }

    // These match JitBuildState::weaken() in build.cpp line 591
    static const std::string_view strong_names[] = {"__fw_export_*", "__global_pointer$"};

    ll_api::ElfFile elf;
    elf.ReadImage(positional[0]);
    elf.WeakenDataSymbols(strong_names);
    if (objectify) {
        elf.ObjectifyExecutable();
    }
    elf.WriteImage(positional[1]);
    return 0;
}
