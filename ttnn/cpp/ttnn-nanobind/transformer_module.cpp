// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_transformer.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/transformer/transformer_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_transformer, mod) {
    mod.doc() = "TTNN transformer operations";

    ttnn::operations::transformer::py_module(mod);
}
