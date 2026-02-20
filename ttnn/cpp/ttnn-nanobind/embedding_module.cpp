// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_embedding.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/embedding/embedding_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_embedding, mod) {
    mod.doc() = "TTNN embedding operations";

    ttnn::operations::embedding::py_module(mod);
}
