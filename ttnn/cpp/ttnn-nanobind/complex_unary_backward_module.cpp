// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_complex_unary_backward.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/eltwise/complex_unary_backward/complex_unary_backward_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_complex_unary_backward, mod) {
    mod.doc() = "TTNN complex_unary_backward operations";

    ttnn::operations::complex_unary_backward::py_module(mod);
}
