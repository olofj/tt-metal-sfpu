// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_embedding_backward.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/embedding_backward/embedding_backward_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_embedding_backward, mod) {
    mod.doc() = "TTNN embedding_backward operations";

    ttnn::operations::embedding_backward::bind_embedding_backward(mod);
}
