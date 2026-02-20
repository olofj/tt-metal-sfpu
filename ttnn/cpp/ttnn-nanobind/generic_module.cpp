// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_generic.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/generic/generic_op_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_generic, mod) {
    mod.doc() = "TTNN generic operations";

    ttnn::operations::generic::bind_generic_operation(mod);
}
