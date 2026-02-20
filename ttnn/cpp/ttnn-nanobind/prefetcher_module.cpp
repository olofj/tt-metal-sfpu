// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_prefetcher.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/prefetcher/prefetcher_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_prefetcher, mod) {
    mod.doc() = "TTNN prefetcher operations";

    ttnn::operations::prefetcher::py_module(mod);
}
