// Smoke test: verify that all external dependencies compile and link.
// This file includes at least one header from each declared dependency.

// BCR dependencies
#include <boost/algorithm/string/trim.hpp>
#include <boost/container/vector.hpp>
#include <boost/core/lightweight_test.hpp>
#include <boost/interprocess/shared_memory_object.hpp>
#include <boost/smart_ptr/make_shared.hpp>
#include <boost/smart_ptr/shared_ptr.hpp>
#include <yaml-cpp/yaml.h>
#include <fmt/core.h>
#include <nlohmann/json.hpp>
#include <range/v3/view/iota.hpp>
#include <spdlog/spdlog.h>
#include <flatbuffers/flatbuffers.h>
#include <google/protobuf/message_lite.h>
#include <benchmark/benchmark.h>
#include <gtest/gtest.h>

// Non-BCR dependencies
#include <capnp/common.h>
#include <simde/x86/sse2.h>
#include <taskflow/taskflow.hpp>
#include <reflect>
#include <enchantum/enchantum.hpp>
#include <tt-logger/tt-logger.hpp>
#include <xtl/xbasic_fixed_string.hpp>
#include <xtensor/core/xlayout.hpp>
#include <xtensor-blas/xblas_config.hpp>
#include <picosha2.h>
#include <asio/version.hpp>

// System libraries are link-only (no headers to include from our wrapper)

#include <cstdio>
#include <string>

int main() {
    // Touch each dependency to prevent dead-code elimination
    boost::container::vector<int> bv{1, 2, 3};
    auto sp = boost::make_shared<int>(42);
    (void)bv;
    (void)sp;

    std::string s = "  hello  ";
    boost::algorithm::trim(s);
    (void)s;

    YAML::Node node;
    node["key"] = "value";

    auto msg = fmt::format("fmt works: {}", 42);
    (void)msg;

    nlohmann::json j;
    j["smoke"] = "test";

    auto rng = ranges::views::iota(0, 5);
    (void)rng;

    spdlog::info("spdlog works");

    flatbuffers::FlatBufferBuilder fbb;
    (void)fbb;

    tf::Taskflow taskflow;
    (void)taskflow;

    auto sha_hash = picosha2::hash256_hex_string(std::string("test"));
    (void)sha_hash;

    (void)ASIO_VERSION;

    std::printf("All dependencies resolved successfully.\n");
    return 0;
}
