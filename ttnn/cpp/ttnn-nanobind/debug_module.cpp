// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_debug.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/debug/debug_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_debug, mod) {
    mod.doc() = "TTNN debug operations";

    ttnn::operations::debug::py_module(mod);
}
