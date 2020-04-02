import PromiseKit
@testable import SignalServiceKit
import XCTest

class OnionRequestAPITests : XCTestCase {

    /// Builds a path and then routes the same request through it several times. Logs the number of successes
    /// versus the number of failures.
    func testOnionRequestSending() {
        let semaphore = DispatchSemaphore(value: 0)
        LokiAPI.getRandomSnode().then(on: OnionRequestAPI.workQueue) { snode -> Promise<LokiAPITarget> in
            return OnionRequestAPI.getPath(excluding: snode).map(on: OnionRequestAPI.workQueue) { _ in snode }
        }.done(on: OnionRequestAPI.workQueue) { snode in
            var successCount = 0
            var failureCount = 0
            let promises: [Promise<Void>] = (0..<8).map { _ in
                let mockSessionID = "0582bc30f11e8a9736407adcaca03b049f4acd4af3ae7eb6b6608d30f0b1e6a20e"
                let parameters: JSON = [ "pubKey" : mockSessionID ]
                let (promise, seal) = Promise<Void>.pending()
                OnionRequestAPI.invoke(.getSwarm, on: snode, with: parameters).done(on: OnionRequestAPI.workQueue) { _ in
                    successCount += 1
                    seal.fulfill(())
                }.catch(on: OnionRequestAPI.workQueue) { error in
                    failureCount += 1
                    seal.reject(error)
                }.finally(on: OnionRequestAPI.workQueue) {
                    let percentage = (successCount == 0) ? 0 : (failureCount == 0) ? 100 : (100 * Double(successCount))/Double(failureCount)
                    print("[Loki] [Onion Request API] Succes %: \(percentage).")
                }
                return promise
            }
            when(resolved: promises).done(on: OnionRequestAPI.workQueue) { _ in
                semaphore.signal()
            }
        }.catch(on: OnionRequestAPI.workQueue) { error in
            print("[Loki] [Onion Request API] Path building failed due to error: \(error).")
            semaphore.signal()
        }
        semaphore.wait()
    }

    // TODO: Test error handling
}
