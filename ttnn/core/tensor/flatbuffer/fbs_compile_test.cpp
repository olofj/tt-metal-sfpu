// Verify that Bazel-generated FlatBuffer headers compile and link correctly.
// Tests cross-directory include resolution for mesh_coordinate.fbs.

#include "mesh_shape_generated.h"
#include "tensor_generated.h"
#include "tensor_spec_generated.h"
#include "tensor_topology_generated.h"

#include <gtest/gtest.h>

TEST(TtnnFbsCompileTest, MeshShape) {
    flatbuffers::FlatBufferBuilder builder;
    std::vector<uint32_t> dims = {2, 4};
    auto shape = ttnn::flatbuffer::CreateMeshShapeDirect(builder, &dims);
    builder.Finish(shape);

    auto* parsed = flatbuffers::GetRoot<ttnn::flatbuffer::MeshShape>(
        builder.GetBufferPointer());
    ASSERT_NE(parsed, nullptr);
    ASSERT_NE(parsed->dimensions(), nullptr);
    EXPECT_EQ(parsed->dimensions()->size(), 2u);
    EXPECT_EQ(parsed->dimensions()->Get(0), 2u);
}

TEST(TtnnFbsCompileTest, TensorSpec) {
    flatbuffers::FlatBufferBuilder builder;
    std::vector<uint32_t> shape = {1, 3, 224, 224};
    auto spec = ttnn::flatbuffer::CreateTensorSpecDirect(builder, &shape);
    builder.Finish(spec);

    auto* parsed = flatbuffers::GetRoot<ttnn::flatbuffer::TensorSpec>(
        builder.GetBufferPointer());
    ASSERT_NE(parsed, nullptr);
    ASSERT_NE(parsed->shape(), nullptr);
    EXPECT_EQ(parsed->shape()->size(), 4u);
}
