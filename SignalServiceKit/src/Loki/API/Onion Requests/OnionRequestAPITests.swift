@testable import SignalServiceKit
import XCTest

class OnionRequestAPITests : XCTestCase {
    private let maxRetryCount: UInt = 2 // Be a bit more stringent when testing

    // TODO: Remove dependency on SSKEnvironment

    func testGetPath() {
        let semaphore = DispatchSemaphore(value: 0)
        var error: Error? = nil
        let _ = OnionRequestAPI.getPath().retryingIfNeeded(maxRetryCount: maxRetryCount).done(on: OnionRequestAPI.workQueue) { _ in
            semaphore.signal()
        }.catch(on: OnionRequestAPI.workQueue) {
            error = $0; semaphore.signal()
        }
        semaphore.wait()
        XCTAssert(error == nil)
    }

    // TODO: Add request sending test
    // TODO: Add error handling test
}
