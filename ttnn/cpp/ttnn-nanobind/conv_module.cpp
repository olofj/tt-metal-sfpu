// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_conv.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/conv/conv_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_conv, mod) {
    mod.doc() = "TTNN conv operations";

    ttnn::operations::conv::py_module(mod);
}
