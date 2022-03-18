// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

import Quick
import Nimble

@testable import SessionMessagingKit

class OpenGroupSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        describe("an Open Group") {
            context("when initializing") {
                it("generates the id") {
                    let openGroup: OpenGroup = OpenGroup(
                        server: "server",
                        room: "room",
                        publicKey: "1234",
                        name: "name",
                        groupDescription: nil,
                        imageID: nil,
                        infoUpdates: 0
                    )
                    
                    expect(openGroup.id).to(equal("server.room"))
                }
            }
            
            context("when NSCoding") {
                // Note: Unit testing NSCoder is horrible so we won't do it properly - wait until we refactor it to Codable
                it("successfully encodes and decodes") {
                    let openGroupToEncode: OpenGroup = OpenGroup(
                        server: "server",
                        room: "room",
                        publicKey: "1234",
                        name: "name",
                        groupDescription: "desc",
                        imageID: "image",
                        infoUpdates: 1
                    )
                    let encodedData: Data = try! NSKeyedArchiver.archivedData(withRootObject: openGroupToEncode, requiringSecureCoding: false)
                    let openGroup: OpenGroup? = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encodedData) as? OpenGroup
                    
                    expect(openGroup).toNot(beNil())
                    expect(openGroup?.id).to(equal("server.room"))
                    expect(openGroup?.server).to(equal("server"))
                    expect(openGroup?.room).to(equal("room"))
                    expect(openGroup?.publicKey).to(equal("1234"))
                    expect(openGroup?.name).to(equal("name"))
                    expect(openGroup?.groupDescription).to(equal("desc"))
                    expect(openGroup?.imageID).to(equal("image"))
                    expect(openGroup?.infoUpdates).to(equal(1))
                }
            }
            
            context("when describing") {
                it("includes relevant information") {
                    let openGroup: OpenGroup = OpenGroup(
                        server: "server",
                        room: "room",
                        publicKey: "1234",
                        name: "name",
                        groupDescription: nil,
                        imageID: nil,
                        infoUpdates: 0
                    )
                    
                    expect(openGroup.description)
                        .to(equal("name (Server: server, Room: room)"))
                }
            }
            
            context("when describing in debug") {
                it("includes relevant information") {
                    let openGroup: OpenGroup = OpenGroup(
                        server: "server",
                        room: "room",
                        publicKey: "1234",
                        name: "name",
                        groupDescription: nil,
                        imageID: nil,
                        infoUpdates: 0
                    )
                    
                    expect(openGroup.debugDescription)
                        .to(equal("OpenGroup(server: \"server\", room: \"room\", id: \"server.room\", publicKey: \"1234\", name: \"name\", groupDescription: null, imageID: null, infoUpdates: 0)"))
                }
            }
        }
    }
}
