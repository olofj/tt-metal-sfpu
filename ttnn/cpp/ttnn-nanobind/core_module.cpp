// SPDX-FileCopyrightText: © 2025 Tenstorrent AI ULC
//
// SPDX-License-Identifier: Apache-2.0

// Entry point for _ttnn_core.so — the core-only split of _ttnn.so.
//
// Binds all types and core functions (Tensor, Device, MemoryConfig, etc.)
// but does NOT bind any operation functions (matmul, bernoulli, etc.).
// Operations are bound in separate per-operation modules (e.g., _ttnn_bernoulli.so)
// that share types via nanobind's NB_DOMAIN cross-module mechanism.
//
// operations::core and operations::trace are included because they define
// types (DeviceComputeKernelConfig, MeshTraceId) that operations depend on.

#include <cstdint>

#include <nanobind/nanobind.h>

#include "ttnn-nanobind/activation.hpp"
#include "ttnn-nanobind/cluster.hpp"
#include "ttnn-nanobind/core.hpp"
#include "ttnn-nanobind/device.hpp"
#include "ttnn-nanobind/events.hpp"
#include "ttnn-nanobind/fabric.hpp"
#include "ttnn-nanobind/global_circular_buffer.hpp"
#include "ttnn-nanobind/global_semaphore.hpp"
#include "ttnn-nanobind/hd_socket.hpp"
#include "ttnn-nanobind/mesh_socket.hpp"
#include "ttnn-nanobind/operations/core.hpp"
#include "ttnn-nanobind/operations/trace.hpp"
#include "ttnn-nanobind/profiler.hpp"
#include "ttnn-nanobind/program_descriptors.hpp"
#include "ttnn-nanobind/reports.hpp"
#include "ttnn-nanobind/tensor.hpp"
#include "ttnn-nanobind/tensor_accessor_args.hpp"
#include "ttnn-nanobind/types.hpp"

#include "ttnn/core.hpp"
#include "ttnn/distributed/distributed_nanobind.hpp"
#include "ttnn/graph/graph_nanobind.hpp"

namespace nb = nanobind;

NB_MODULE(_ttnn_core, mod) {
    mod.doc() = "TTNN core types and functions (no operation bindings)";

    // MODULES
    auto m_deprecated = mod.def_submodule("deprecated", "Deprecated tt_lib bindings");
    auto m_tensor = mod.def_submodule("tensor", "ttnn tensor");

    auto m_depr_operations = m_deprecated.def_submodule("operations", "Submodule for experimental operations");
    [[maybe_unused]] auto m_primary_ops = m_depr_operations.def_submodule("primary", "Primary operations");

    auto m_graph = mod.def_submodule("graph", "Contains graph capture functions");
    auto m_types = mod.def_submodule("types", "ttnn Types");
    auto m_activation = mod.def_submodule("activation", "ttnn Activation");
    auto m_cluster = mod.def_submodule("cluster", "ttnn cluster");
    auto m_core = mod.def_submodule("core", "core functions");
    auto m_device = mod.def_submodule("device", "ttnn devices");
    auto m_multi_device = mod.def_submodule("multi_device", "ttnn multi_device");
    auto m_events = mod.def_submodule("events", "ttnn events");
    auto m_global_circular_buffer = mod.def_submodule("global_circular_buffer", "ttnn global circular buffer");
    auto m_global_semaphore = mod.def_submodule("global_semaphore", "ttnn global semaphore");
    auto m_hd_socket = mod.def_submodule("hd_socket", "ttnn host-device sockets");
    auto m_mesh_socket = mod.def_submodule("mesh_socket", "ttnn mesh socket");
    auto m_profiler = mod.def_submodule("profiler", "Submodule defining the profiler");
    auto m_reports = mod.def_submodule("reports", "ttnn reports");
    auto m_operations = mod.def_submodule("operations", "ttnn Operations");
    auto m_fabric = mod.def_submodule("fabric", "Fabric instantiation APIs");
    auto m_program_descriptors = mod.def_submodule("program_descriptor", "Program descriptors types");
    auto m_tensor_accessor_args = mod.def_submodule("tensor_accessor_args", "Tensor accessor args types");

    // TYPES
    ttnn::tensor::tensor_mem_config_module_types(m_tensor);
    ttnn::tensor::pytensor_module_types(m_tensor);
    ttnn::graph::py_graph_module_types(m_graph);

    ttnn::types::py_module_types(m_types);
    ttnn::activation::py_module_types(m_activation);
    ttnn::cluster::py_cluster_module_types(m_cluster);
    ttnn::core::py_module_types(m_core);
    ttnn::device::py_device_module_types(m_device);
    ttnn::fabric::bind_fabric_api(m_fabric);
    ttnn::distributed::py_module_types(m_multi_device);
    ttnn::events::py_module_types(m_events);
    ttnn::global_circular_buffer::py_module_types(m_global_circular_buffer);
    ttnn::global_semaphore::py_module_types(m_global_semaphore);
    ttnn::hd_socket::py_module_types(m_hd_socket);
    ttnn::mesh_socket::py_module_types(m_mesh_socket);
    ttnn::reports::py_module_types(m_reports);
    ttnn::program_descriptors::py_module_types(m_program_descriptors);
    ttnn::tensor_accessor_args::py_module_types(m_tensor_accessor_args);

    // FUNCTIONS
    ttnn::tensor::tensor_mem_config_module(m_tensor);
    ttnn::tensor::pytensor_module(m_tensor);
    ttnn::core::py_module(m_core);
    ttnn::graph::py_graph_module(m_graph);

    ttnn::types::py_module(m_types);
    ttnn::activation::py_module(m_activation);
    ttnn::cluster::py_cluster_module(m_cluster);
    ttnn::device::py_device_module(m_device);
    ttnn::distributed::py_module(m_multi_device);
    ttnn::events::py_module(m_events);
    ttnn::global_circular_buffer::py_module(m_global_circular_buffer);
    ttnn::global_semaphore::py_module(m_global_semaphore);
    ttnn::hd_socket::py_module(m_hd_socket);
    ttnn::mesh_socket::py_module(m_mesh_socket);
    ttnn::profiler::py_module(m_profiler);
    ttnn::reports::py_module(m_reports);
    ttnn::tensor_accessor_args::py_module(m_tensor_accessor_args);

    // Bind operations::core and operations::trace type definitions.
    // These define DeviceComputeKernelConfig, MeshTraceId, etc. that
    // per-operation modules depend on via cross-module type sharing.
    auto m_ops_core = m_operations.def_submodule("core", "core operations");
    ttnn::operations::core::py_module_types(m_ops_core);
    ttnn::operations::core::py_module(m_ops_core);

    auto m_ops_trace = m_operations.def_submodule("trace", "trace operations");
    ttnn::operations::trace::py_module_types(m_ops_trace);
    ttnn::operations::trace::py_module(m_ops_trace);

    // Top-level module attributes and utility functions.
    mod.attr("CONFIG") = &ttnn::CONFIG;
    mod.def(
        "get_python_operation_id",
        []() -> std::uint64_t { return ttnn::CoreIDs::instance().get_python_operation_id(); },
        "Get operation id");
    mod.def(
        "set_python_operation_id",
        [](std::uint64_t id) { ttnn::CoreIDs::instance().set_python_operation_id(id); },
        "Set operation id");
    mod.def(
        "fetch_and_increment_python_operation_id",
        []() -> std::uint64_t { return ttnn::CoreIDs::instance().fetch_and_increment_python_operation_id(); },
        "Increment tensor id and return the previously held id");

    mod.def("get_tensor_id", &tt::tt_metal::Tensor::get_tensor_id_counter, "Get the current tensor ID counter value");
    mod.def(
        "set_tensor_id",
        &tt::tt_metal::Tensor::set_tensor_id_counter,
        nb::arg("id"),
        "Set the tensor ID counter to a specific value");
    mod.def(
        "fetch_and_increment_tensor_id",
        &tt::tt_metal::Tensor::next_tensor_id,
        "Atomically fetch and increment the tensor ID counter");

    mod.def(
        "get_device_operation_id",
        []() -> std::uint64_t { return ttnn::CoreIDs::instance().get_device_operation_id(); },
        "Get device operation id");
    mod.def(
        "set_device_operation_id",
        [](std::uint64_t id) { ttnn::CoreIDs::instance().set_device_operation_id(id); },
        "Set device operation id");
    mod.def(
        "fetch_and_increment_device_operation_id",
        []() -> std::uint64_t { return ttnn::CoreIDs::instance().fetch_and_increment_device_operation_id(); },
        "Increment device operation id and return the previously held id");
}
