// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_sliding_window.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/sliding_window/sliding_window_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_sliding_window, mod) {
    mod.doc() = "TTNN sliding_window operations";

    ttnn::operations::sliding_window::bind_sliding_window(mod);
}
