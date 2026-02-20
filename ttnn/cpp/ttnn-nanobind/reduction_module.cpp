// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_reduction.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/reduction/reduction_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_reduction, mod) {
    mod.doc() = "TTNN reduction operations";

    ttnn::operations::reduction::py_module(mod);
}
