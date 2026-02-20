// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_data_movement.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/data_movement/data_movement_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_data_movement, mod) {
    mod.doc() = "TTNN data_movement operations";

    ttnn::operations::data_movement::py_module(mod);
}
