// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_rand.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/rand/rand_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_rand, mod) {
    mod.doc() = "TTNN rand operations";

    ttnn::operations::rand::bind_rand_operation(mod);
}
