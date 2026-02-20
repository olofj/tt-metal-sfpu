// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_loss.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/loss/loss_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_loss, mod) {
    mod.doc() = "TTNN loss operations";

    ttnn::operations::loss::bind_loss_functions(mod);
}
