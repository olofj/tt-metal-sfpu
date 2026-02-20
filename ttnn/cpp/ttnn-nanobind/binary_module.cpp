// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_binary.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/eltwise/binary/binary_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_binary, mod) {
    mod.doc() = "TTNN binary operations";

    ttnn::operations::binary::py_module(mod);
}
