// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_experimental.so — experimental operations split module.
//
// Dispatches to all experimental sub-package bindings via the top-level
// experimental::py_module() function. Types are provided by _ttnn_core.so
// via nanobind's NB_DOMAIN cross-module type sharing.

#include <nanobind/nanobind.h>

#include "ttnn/operations/experimental/experimental_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_experimental, mod) {
    mod.doc() = "TTNN experimental operations";

    ttnn::operations::experimental::py_module(mod);
}
