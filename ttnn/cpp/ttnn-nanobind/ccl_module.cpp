// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_ccl.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/ccl/ccl_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_ccl, mod) {
    mod.doc() = "TTNN ccl operations";

    ttnn::operations::ccl::py_module(mod);
}
