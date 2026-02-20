// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_normalization.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/normalization/normalization_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_normalization, mod) {
    mod.doc() = "TTNN normalization operations";

    ttnn::operations::normalization::py_module(mod);
}
