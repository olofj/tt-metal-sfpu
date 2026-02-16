// Verify that Bazel-generated FlatBuffer headers compile and link correctly.
// Instantiates one type from each schema to confirm codegen is complete.

#include "base_types_generated.h"
#include "buffer_types_generated.h"
#include "command_generated.h"
#include "light_metal_binary_generated.h"
#include "program_types_generated.h"

#include <gtest/gtest.h>

TEST(ImplFbsCompileTest, InstantiateTypes) {
    // base_types: scoped enum
    EXPECT_EQ(
        tt::tt_metal::flatbuffer::Arch::Blackhole,
        static_cast<tt::tt_metal::flatbuffer::Arch>(2));

    // program_types: table
    flatbuffers::FlatBufferBuilder builder;
    auto core = tt::tt_metal::flatbuffer::CreateCoreCoord(builder, 1, 2);
    builder.Finish(core);

    auto* coord = flatbuffers::GetRoot<tt::tt_metal::flatbuffer::CoreCoord>(
        builder.GetBufferPointer());
    EXPECT_EQ(coord->x(), 1);
    EXPECT_EQ(coord->y(), 2);
}

TEST(ImplFbsCompileTest, LightMetalBinaryRoundTrip) {
    flatbuffers::FlatBufferBuilder builder;

    auto binary = tt::tt_metal::flatbuffer::CreateLightMetalBinary(builder);
    builder.Finish(binary);

    auto* parsed = flatbuffers::GetRoot<tt::tt_metal::flatbuffer::LightMetalBinary>(
        builder.GetBufferPointer());
    EXPECT_NE(parsed, nullptr);
}
