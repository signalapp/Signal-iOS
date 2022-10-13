//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class MessagePipelineSupervisorTest: SSKBaseTestSwift {

    var dut: MessagePipelineSupervisor! = nil

    override func setUp() {
        super.setUp()
        dut = MessagePipelineSupervisor(isolated: true)
    }

    func testDefaultState() {
        XCTAssertTrue(dut.isMessageProcessingPermitted)
    }

    func testSuspendAndResume() {
        // Setup
        let handle = dut.suspendMessageProcessing(for: "Testing")

        // Test
        let processingPermittedWitActiveSuppression = dut.isMessageProcessingPermitted
        handle.invalidate()
        let processingPermittedAfterInvalidation = dut.isMessageProcessingPermitted

        // Verify
        XCTAssertFalse(processingPermittedWitActiveSuppression)
        XCTAssertTrue(processingPermittedAfterInvalidation)
    }

    func testSuspendNotifications() {
        // Setup
        let pipelineStage = MockPipelineStage()
        dut.register(pipelineStage: pipelineStage)

        // Test
        let handle = dut.suspendMessageProcessing(for: "Testing")

        // Verify
        XCTAssertEqual(pipelineStage.suspendCalloutCount, 1)
        XCTAssertEqual(pipelineStage.resumeCalloutCount, 0)

        // Clean up
        handle.invalidate()
    }

    func testResumeNotifications() {
        // Setup
        let handle = dut.suspendMessageProcessing(for: "Testing")
        let pipelineStage = MockPipelineStage()
        dut.register(pipelineStage: pipelineStage)

        // Test
        handle.invalidate()

        // Verify
        XCTAssertEqual(pipelineStage.suspendCalloutCount, 0)
        XCTAssertEqual(pipelineStage.resumeCalloutCount, 1)
    }

    func testAddMultipleStages() {
        // Setup
        let addedBeforeSuspension = MockPipelineStage()
        let addedAfterSuspension = MockPipelineStage()
        let addedAfterResume = MockPipelineStage()

        // Test
        dut.register(pipelineStage: addedBeforeSuspension)
        let handle = dut.suspendMessageProcessing(for: "Testing")
        dut.register(pipelineStage: addedAfterSuspension)
        handle.invalidate()
        dut.register(pipelineStage: addedAfterResume)

        // Verify
        XCTAssertEqual(addedBeforeSuspension.suspendCalloutCount, 1)
        XCTAssertEqual(addedBeforeSuspension.resumeCalloutCount, 1)
        XCTAssertEqual(addedAfterSuspension.suspendCalloutCount, 0)
        XCTAssertEqual(addedAfterSuspension.resumeCalloutCount, 1)
        XCTAssertEqual(addedAfterResume.suspendCalloutCount, 0)
        XCTAssertEqual(addedAfterResume.resumeCalloutCount, 0)
    }

    func testMultiRegister() {
        // Setup
        let stage = MockPipelineStage()

        // Test
        dut.register(pipelineStage: stage)
        dut.register(pipelineStage: stage)
        dut.register(pipelineStage: stage)

        let handle = dut.suspendMessageProcessing(for: "Testing")

        dut.unregister(pipelineStage: stage)

        handle.invalidate()

        // Verify
        XCTAssertEqual(stage.suspendCalloutCount, 1)
        XCTAssertEqual(stage.resumeCalloutCount, 0)
    }

    func testRemoveMultipleStages() {
        // Setup
        let removedBeforeSuspension = MockPipelineStage()
        let removedAfterSuspension = MockPipelineStage()
        let removedAfterResume = MockPipelineStage()
        dut.register(pipelineStage: removedBeforeSuspension)
        dut.register(pipelineStage: removedAfterSuspension)
        dut.register(pipelineStage: removedAfterResume)

        // Test
        dut.unregister(pipelineStage: removedBeforeSuspension)
        let handle = dut.suspendMessageProcessing(for: "Testing")
        dut.unregister(pipelineStage: removedAfterSuspension)
        handle.invalidate()
        dut.unregister(pipelineStage: removedAfterResume)

        // Verify
        XCTAssertEqual(removedBeforeSuspension.suspendCalloutCount, 0)
        XCTAssertEqual(removedBeforeSuspension.resumeCalloutCount, 0)
        XCTAssertEqual(removedAfterSuspension.suspendCalloutCount, 1)
        XCTAssertEqual(removedAfterSuspension.resumeCalloutCount, 0)
        XCTAssertEqual(removedAfterResume.suspendCalloutCount, 1)
        XCTAssertEqual(removedAfterResume.resumeCalloutCount, 1)
    }

    func testRepeatedInvalidation() {
        // Setup
        let pipelineStage = MockPipelineStage()
        dut.register(pipelineStage: pipelineStage)
        let handle = dut.suspendMessageProcessing(for: "Testing")

        // Test, repeatedly invalidate. Then try and re-suspend
        handle.invalidate()
        handle.invalidate()
        handle.invalidate()
        let handle2 = dut.suspendMessageProcessing(for: "Round 2")

        // Verify, repeated invalidations of same handle don't mess with reference count
        XCTAssertEqual(pipelineStage.suspendCalloutCount, 2)
        XCTAssertEqual(pipelineStage.resumeCalloutCount, 1)

        // Clean Up
        handle2.invalidate()
    }

    func testPipelineStageDealloc() {
        // Setup
        var calloutCount = 0
        var handle: MessagePipelineSuspensionHandle?

        autoreleasepool {
            // Construct stage within autoreleasepool
            let stage: MockPipelineStage? = MockPipelineStage()
            stage?.calloutBlock = {
                calloutCount += 1
            }
            dut.register(pipelineStage: stage!)

            // Take out a handle, then nil out the stage
            handle = dut.suspendMessageProcessing(for: "Testing")
        }
        // Invalidate the handle
        handle?.invalidate()

        // Verify, we should only get one callout before the weak hashtable loses the stage
        XCTAssertEqual(calloutCount, 1)
    }
}

extension MessagePipelineSupervisorTest {

    class MockPipelineStage: MessageProcessingPipelineStage {
        var suspendCalloutCount = 0
        var resumeCalloutCount = 0
        var calloutBlock: (() -> Void)?

        func supervisorDidSuspendMessageProcessing(_ supervisor: MessagePipelineSupervisor) {
            suspendCalloutCount += 1
            calloutBlock?()
        }

        func supervisorDidResumeMessageProcessing(_ supervisor: MessagePipelineSupervisor) {
            resumeCalloutCount += 1
            calloutBlock?()
        }
    }

}
