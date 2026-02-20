// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_quantization.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/eltwise/quantization/quantization_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_quantization, mod) {
    mod.doc() = "TTNN quantization operations";

    ttnn::operations::quantization::py_module(mod);
}
