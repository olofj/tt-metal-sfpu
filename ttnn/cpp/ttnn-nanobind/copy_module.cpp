// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_copy.so — copy operations split module.
//
// Binding source lives in ttnn-nanobind/operations/copy.cpp (not in an
// operations sub-package). Types are provided by _ttnn_core.so via
// nanobind's NB_DOMAIN cross-module type sharing.

#include <nanobind/nanobind.h>

#include "ttnn-nanobind/operations/copy.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_copy, mod) {
    mod.doc() = "TTNN copy operations";

    ttnn::operations::copy::py_module(mod);
}
