// SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_pool.so — a multi-binding split module.
//
// Binds all pool operations (max_pool2d, avg_pool2d, global_avg_pool,
// rotate, upsample, grid_sample). Types are provided by _ttnn_core.so
// via nanobind's NB_DOMAIN cross-module type sharing.

#include <nanobind/nanobind.h>

#include "ttnn/operations/pool/generic/generic_pools_nanobind.hpp"
#include "ttnn/operations/pool/global_avg_pool/global_avg_pool_nanobind.hpp"
#include "ttnn/operations/pool/grid_sample/grid_sample_nanobind.hpp"
#include "ttnn/operations/pool/rotate/rotate_nanobind.hpp"
#include "ttnn/operations/pool/upsample/upsample_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_pool, mod) {
    mod.doc() = "TTNN pool operations";

    ttnn::operations::pool::py_module(mod);
    ttnn::operations::avgpool::py_module(mod);
    ttnn::operations::rotate::py_module(mod);
    ttnn::operations::upsample::py_module(mod);
    ttnn::operations::grid_sample::bind_grid_sample(mod);
}
