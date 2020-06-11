import XCTest

extension XCTestCase {

    /// A helper for asynchronous testing.
    ///
    /// Usage example:
    ///
    /// ```
    /// func testSomething() {
    ///     doAsyncThings()
    ///     eventually {
    ///         /* XCTAssert goes here... */
    ///     }
    /// }
    /// ```
    ///
    /// The provided closure won't execute until `timeout` seconds have passed. Pass
    /// in a timeout long enough for your asynchronous process to finish if it's
    /// expected to take more than the default 0.1 second.
    ///
    /// - Parameters:
    ///   - timeout: number of seconds to wait before executing `closure`.
    ///   - closure: a closure to execute when `timeout` seconds have passed.
    ///
    /// - Note: `timeout` must be less than 60 seconds.
    func eventually(timeout: TimeInterval = 0.1, closure: @escaping () -> Void) {
        assert(timeout < 60)
        let expectation = self.expectation(description: "")
        expectation.fulfillAfter(timeout)
        self.waitForExpectations(timeout: 60) { _ in
            closure()
        }
    }
}

extension XCTestExpectation {

    /// Call `fulfill()` after some time.
    ///
    /// - Parameter time: number of seconds after which `fulfill()` will be called.
    func fulfillAfter(_ time: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + time) {
            self.fulfill()
        }
    }
}
