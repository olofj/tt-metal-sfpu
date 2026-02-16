// Verify that Bazel-generated FlatBuffer headers compile and link correctly.
// Tests cross-directory include resolution for mesh_coordinate.fbs
// referenced via: include "tt-metalium/serialized_descriptors/mesh_coordinate.fbs"

#include "socket_peer_descriptor_generated.h"

#include <gtest/gtest.h>

TEST(DistributedFbsCompileTest, SocketPeerDescriptor) {
    flatbuffers::FlatBufferBuilder builder;
    auto desc = tt::tt_metal::distributed::flatbuffer::CreateSocketPeerDescriptor(builder);
    builder.Finish(desc);

    auto* parsed = flatbuffers::GetRoot<
        tt::tt_metal::distributed::flatbuffer::SocketPeerDescriptor>(
        builder.GetBufferPointer());
    EXPECT_NE(parsed, nullptr);
}
