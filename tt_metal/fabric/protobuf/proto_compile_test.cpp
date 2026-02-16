// Verify that Bazel-generated protobuf headers compile and link correctly.
// Instantiates one message from each .proto file to confirm codegen is complete.

#include "tt_metal/fabric/protobuf/intermesh_connection_table.pb.h"
#include "tt_metal/fabric/protobuf/mesh_graph_descriptor.pb.h"
#include "tt_metal/fabric/protobuf/physical_system_descriptor.pb.h"
#include "tt_metal/fabric/protobuf/port_descriptor_table.pb.h"
#include "tt_metal/fabric/protobuf/router_port_directions.pb.h"

#include <gtest/gtest.h>

TEST(FabricProtoCompileTest, InstantiateMessages) {
    tt::tt_fabric::proto::MeshGraphDescriptor mgd;
    EXPECT_EQ(mgd.mesh_descriptors_size(), 0);

    tt::fabric::proto::PhysicalSystemDescriptor psd;
    EXPECT_EQ(psd.asic_descriptors_size(), 0);

    tt::tt_fabric::protobuf::RouterPortDirectionsMap rpdm;
    EXPECT_FALSE(rpdm.has_local_mesh_id());

    tt::fabric::proto::PortDescriptorTable pdt;
    EXPECT_EQ(pdt.mesh_maps_size(), 0);

    tt::fabric::proto::ConnectionsTable ct;
    EXPECT_EQ(ct.connections_size(), 0);
}

TEST(FabricProtoCompileTest, RoundTripSerialization) {
    tt::fabric::proto::ConnectionsTable original;
    auto* conn = original.add_connections();
    auto* first = conn->mutable_first();
    first->set_id(42);
    first->set_port_direction(1);
    first->set_port_channel(3);

    std::string serialized;
    ASSERT_TRUE(original.SerializeToString(&serialized));

    tt::fabric::proto::ConnectionsTable deserialized;
    ASSERT_TRUE(deserialized.ParseFromString(serialized));
    ASSERT_EQ(deserialized.connections_size(), 1);
    EXPECT_EQ(deserialized.connections(0).first().id(), 42);
    EXPECT_EQ(deserialized.connections(0).first().port_direction(), 1);
    EXPECT_EQ(deserialized.connections(0).first().port_channel(), 3);
}
