// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_kv_cache.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/kv_cache/kv_cache_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_kv_cache, mod) {
    mod.doc() = "TTNN kv_cache operations";

    ttnn::operations::kv_cache::bind_kv_cache(mod);
}
