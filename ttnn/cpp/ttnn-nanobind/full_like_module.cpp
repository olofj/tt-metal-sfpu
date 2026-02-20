// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_full_like.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/full_like/full_like_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_full_like, mod) {
    mod.doc() = "TTNN full_like operations";

    ttnn::operations::full_like::bind_full_like_operation(mod);
}
