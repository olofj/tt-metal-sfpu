// SPDX-FileCopyrightText: © 2025 Tenstorrent AI ULC
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_bernoulli.so — a single-operation split module.
//
// Binds only the bernoulli operation. Types (Tensor, MemoryConfig, etc.)
// are provided by _ttnn_core.so via nanobind's NB_DOMAIN cross-module
// type sharing — both modules use NB_DOMAIN=ttnn.

#include <nanobind/nanobind.h>

#include "ttnn/operations/bernoulli/bernoulli_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_bernoulli, mod) {
    mod.doc() = "TTNN bernoulli operation";

    ttnn::operations::bernoulli::bind_bernoulli_operation(mod);
}
