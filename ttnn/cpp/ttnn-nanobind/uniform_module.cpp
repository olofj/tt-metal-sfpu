// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_uniform.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/uniform/uniform_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_uniform, mod) {
    mod.doc() = "TTNN uniform operations";

    ttnn::operations::uniform::bind_uniform_operation(mod);
}
