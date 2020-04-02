import CryptoSwift
import PromiseKit
@testable import SignalServiceKit
import XCTest

class OnionRequestAPITests : XCTestCase {

    /// Builds a path and then routes the same request through it several times. Logs the number of successes
    /// versus the number of failures.
    func testOnionRequestSending() {
        let semaphore = DispatchSemaphore(value: 0)
        var totalSuccessRate: Double = 0
        LokiAPI.getRandomSnode().then(on: OnionRequestAPI.workQueue) { snode -> Promise<LokiAPITarget> in
            return OnionRequestAPI.getPath(excluding: snode).map(on: OnionRequestAPI.workQueue) { _ in snode } // Ensure we only build a path once
        }.done(on: OnionRequestAPI.workQueue) { snode in
            var successCount = 0
            var failureCount = 0
            let promises: [Promise<Void>] = (0..<10).map { _ in
                let mockSessionID = "0582bc30f11e8a9736407adcaca03b049f4acd4af3ae7eb6b6608d30f0b1e6a20e"
                let parameters: JSON = [ "pubKey" : mockSessionID ]
                let (promise, seal) = Promise<Void>.pending()
                OnionRequestAPI.invoke(.getSwarm, on: snode, with: parameters).done(on: OnionRequestAPI.workQueue) { data in
                    successCount += 1
                    print("[Loki] [Onion Request API] Onion request succeeded with result: \(String(data: data, encoding: .utf8)).")
                    seal.fulfill(())
                }.catch(on: OnionRequestAPI.workQueue) { error in
                    failureCount += 1
                    if case GCM.Error.fail = error {
                        print("[Loki] [Onion Request API] Onion request failed due a decryption error.")
                    } else {
                        print("[Loki] [Onion Request API] Onion request failed due to error: \(error).")
                    }
                    seal.reject(error)
                }.finally(on: OnionRequestAPI.workQueue) {
                    let currentSuccessRate = min((100 * Double(successCount))/Double(failureCount), 100)
                    print("[Loki] [Onion Request API] Current onion request succes rate: \(String(format: "%.1f", currentSuccessRate))%.")
                }
                return promise
            }
            when(resolved: promises).done(on: OnionRequestAPI.workQueue) { _ in
                totalSuccessRate = min((100 * Double(successCount))/Double(failureCount), 100)
                semaphore.signal()
            }
        }.catch(on: OnionRequestAPI.workQueue) { error in
            print("[Loki] [Onion Request API] Path building failed due to error: \(error).")
            semaphore.signal()
        }
        semaphore.wait()
        print("[Loki] [Onion Request API] Total onion request succes rate: \(String(format: "%.1f", totalSuccessRate))%.")
        XCTAssert(totalSuccessRate >= 90)
    }

    // TODO: Test error handling
    // TODO: Test race condition handling
}
