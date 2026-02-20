// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_full.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/full/full_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_full, mod) {
    mod.doc() = "TTNN full operations";

    ttnn::operations::full::bind_full_operation(mod);
}
