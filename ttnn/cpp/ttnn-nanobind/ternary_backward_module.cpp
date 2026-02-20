// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_ternary_backward.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/eltwise/ternary_backward/ternary_backward_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_ternary_backward, mod) {
    mod.doc() = "TTNN ternary_backward operations";

    ttnn::operations::ternary_backward::py_module(mod);
}
