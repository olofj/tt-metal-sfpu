// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_ternary.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/eltwise/ternary/ternary_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_ternary, mod) {
    mod.doc() = "TTNN ternary operations";

    ttnn::operations::ternary::py_module(mod);
}
