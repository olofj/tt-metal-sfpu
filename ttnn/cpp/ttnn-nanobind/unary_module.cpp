// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_unary.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/eltwise/unary/unary_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_unary, mod) {
    mod.doc() = "TTNN unary operations";

    ttnn::operations::unary::py_module(mod);
}
