// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_creation.so — creation operations split module.
//
// Binding source lives in ttnn-nanobind/operations/creation.cpp (not in an
// operations sub-package). Types are provided by _ttnn_core.so via
// nanobind's NB_DOMAIN cross-module type sharing.

#include <nanobind/nanobind.h>

#include "ttnn-nanobind/operations/creation.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_creation, mod) {
    mod.doc() = "TTNN creation operations";

    ttnn::operations::creation::py_module(mod);
}
