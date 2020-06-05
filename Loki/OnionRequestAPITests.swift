import CryptoSwift
import PromiseKit
@testable import SignalServiceKit
import XCTest

class OnionRequestAPITests : XCTestCase {
    private let maxRetryCount: UInt = 2 // Be a bit more stringent when testing
    private let testPublicKey = "0501da4723331eb54aaa9a6753a0a59f762103de63f1dc40879cb65a5b5f508814"
    
    func testOnionRequestSending() {
        let semaphore = DispatchSemaphore(value: 0)
        var error: Error? = nil
        LokiAPI.useOnionRequests = true
        let _ = attempt(maxRetryCount: maxRetryCount, recoveringOn: LokiAPI.workQueue) { [testPublicKey = self.testPublicKey] in
            LokiAPI.getSwarm(for: testPublicKey)
        }.done(on: LokiAPI.workQueue) { _ in
            semaphore.signal()
        }.catch(on: LokiAPI.workQueue) {
            error = $0; semaphore.signal()
        }
        semaphore.wait()
        XCTAssert(error == nil)
    }
}
