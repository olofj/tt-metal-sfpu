// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_index_fill.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/index_fill/index_fill_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_index_fill, mod) {
    mod.doc() = "TTNN index_fill operations";

    ttnn::operations::index_fill::bind_index_fill_operation(mod);
}
