// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_binary_backward.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/eltwise/binary_backward/binary_backward_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_binary_backward, mod) {
    mod.doc() = "TTNN binary_backward operations";

    ttnn::operations::binary_backward::py_module(mod);
}
