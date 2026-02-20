// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_matmul.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/matmul/matmul_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_matmul, mod) {
    mod.doc() = "TTNN matmul operations";

    ttnn::operations::matmul::py_module(mod);
}
