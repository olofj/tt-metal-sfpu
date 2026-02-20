// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_complex_unary.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/eltwise/complex_unary/complex_unary_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_complex_unary, mod) {
    mod.doc() = "TTNN complex_unary operations";

    ttnn::operations::complex_unary::py_module(mod);
}
