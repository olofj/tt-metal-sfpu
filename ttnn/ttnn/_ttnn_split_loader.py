# SPDX-FileCopyrightText: © 2026 Olof Johansson <olof@lixom.net>

# SPDX-License-Identifier: Apache-2.0

"""Loader for split _ttnn modules.

When the monolithic _ttnn.so is not available (e.g. in Bazel split-module
builds), this module loads _ttnn_core and grafts available per-operation
split modules into its operations namespace so that the rest of ttnn sees
the same module layout as the monolithic build.

Each split module (e.g. _ttnn_bernoulli) binds operations directly onto
its top-level module via bind_registered_operation(). After grafting,
ttnn._ttnn.operations.bernoulli resolves to the _ttnn_bernoulli module,
so ttnn._ttnn.operations.bernoulli.bernoulli works correctly.

The auto_register_ttnn_cpp_operations walk finds operations via the
__ttnn_operation__ attribute regardless of module nesting, and the
python_fully_qualified_name property is set by C++ template parameters
(e.g. "ttnn::bernoulli" -> "ttnn.bernoulli"), not by module path.
"""

import importlib
import sys

_SPLIT_OPS = [
    "bernoulli",
    "binary",
    "binary_backward",
    "ccl",
    "complex",
    "complex_unary",
    "complex_unary_backward",
    "conv",
    "copy",
    "creation",
    "data_movement",
    "debug",
    "embedding",
    "embedding_backward",
    "examples",
    "experimental",
    "full",
    "full_like",
    "generic",
    "index_fill",
    "kv_cache",
    "loss",
    "matmul",
    "moreh",
    "normalization",
    "point_to_point",
    "pool",
    "prefetcher",
    "quantization",
    "rand",
    "reduction",
    "sliding_window",
    "ternary",
    "ternary_backward",
    "transformer",
    "unary",
    "unary_backward",
    "uniform",
]


def load_split_modules():
    """Load _ttnn_core and graft available split operation modules."""
    import ttnn._ttnn_core

    sys.modules["ttnn._ttnn"] = ttnn._ttnn_core

    operations = ttnn._ttnn_core.operations
    for name in _SPLIT_OPS:
        try:
            mod = importlib.import_module(f"ttnn._ttnn_{name}")
            setattr(operations, name, mod)
            sys.modules[f"ttnn._ttnn.operations.{name}"] = mod
        except ImportError:
            pass
