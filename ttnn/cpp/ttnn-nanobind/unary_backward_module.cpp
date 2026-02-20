// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_unary_backward.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/eltwise/unary_backward/unary_backward_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_unary_backward, mod) {
    mod.doc() = "TTNN unary_backward operations";

    ttnn::operations::unary_backward::py_module(mod);
}
