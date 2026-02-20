// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_examples.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/examples/examples_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_examples, mod) {
    mod.doc() = "TTNN examples operations";

    ttnn::operations::examples::py_module(mod);
}
