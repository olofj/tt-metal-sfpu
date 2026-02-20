// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_complex.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/eltwise/complex/complex_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_complex, mod) {
    mod.doc() = "TTNN complex operations";

    ttnn::operations::complex::py_module(mod);
}
