// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_point_to_point.so — a single-operation split module.

#include <nanobind/nanobind.h>

#include "ttnn/operations/point_to_point/point_to_point_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_point_to_point, mod) {
    mod.doc() = "TTNN point_to_point operations";

    ttnn::operations::point_to_point::bind_point_to_point(mod);
}
