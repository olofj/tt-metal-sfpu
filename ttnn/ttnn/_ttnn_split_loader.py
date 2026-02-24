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

import ctypes
import importlib
import os
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


def _register_submodules(module, prefix, _seen=None):
    """Recursively register nanobind submodules in sys.modules."""
    if _seen is None:
        _seen = set()
    mod_id = id(module)
    if mod_id in _seen:
        return
    _seen.add(mod_id)
    for name in dir(module):
        if name.startswith("_"):
            continue
        obj = getattr(module, name, None)
        if type(obj).__name__ == "module":
            key = f"{prefix}.{name}"
            sys.modules[key] = obj
            _register_submodules(obj, key, _seen)


def load_split_modules():
    """Load _ttnn_core and graft available split operation modules."""
    # Use RTLD_GLOBAL | RTLD_LAZY for ALL split modules including _ttnn_core:
    # - RTLD_GLOBAL: symbols are shared across all split .so files so that
    #   singletons like MetalContext::instance() have a single copy.  Without
    #   this, each .so gets its own MetalContext, causing UMD CHIP_IN_USE
    #   mutex deadlocks when multiple Cluster objects try to open the same
    #   PCIe device.
    # - RTLD_LAZY: defer symbol resolution (Python defaults to RTLD_NOW which
    #   requires all symbols resolved at dlopen time).
    old_flags = sys.getdlopenflags()
    sys.setdlopenflags(ctypes.RTLD_GLOBAL | os.RTLD_LAZY)

    import ttnn._ttnn_core

    sys.modules["ttnn._ttnn"] = ttnn._ttnn_core
    # Also set the attribute on the ttnn package so that `import ttnn._ttnn`
    # works during ttnn's own __init__.py (the module is partially initialized
    # at this point, so Python can't resolve the attribute automatically).
    import ttnn

    ttnn._ttnn = ttnn._ttnn_core

    # Register all nanobind submodules (multi_device, events, device,
    # operations.trace, etc.) in sys.modules so that dotted imports like
    # `from ttnn._ttnn.multi_device import ...` work. Walk recursively
    # because some submodules (e.g. operations) contain nested submodules.
    _register_submodules(ttnn._ttnn_core, "ttnn._ttnn")

    operations = ttnn._ttnn_core.operations
    loaded_split_modules = []
    for name in _SPLIT_OPS:
        try:
            mod = importlib.import_module(f"ttnn._ttnn_{name}")
            setattr(operations, name, mod)
            sys.modules[f"ttnn._ttnn.operations.{name}"] = mod
            loaded_split_modules.append(mod)
        except ImportError:
            pass

    sys.setdlopenflags(old_flags)

    # Store for auto_register_ttnn_cpp_operations to use later, since
    # dir() on a nanobind C module may not include dynamically-set attributes.
    global _loaded_split_modules
    _loaded_split_modules = loaded_split_modules
