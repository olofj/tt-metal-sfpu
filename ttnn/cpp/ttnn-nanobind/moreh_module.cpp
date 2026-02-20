// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_moreh.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/moreh/moreh_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_moreh, mod) {
    mod.doc() = "TTNN moreh operations";

    ttnn::operations::moreh::bind_moreh_operations(mod);
}
