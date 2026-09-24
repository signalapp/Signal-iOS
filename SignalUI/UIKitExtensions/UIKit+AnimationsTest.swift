//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import UIKit
import XCTest

final class UIKitAnimationsTest: XCTestCase {

    private static let timeout: TimeInterval = 5

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.isHidden = false
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    // MARK: - setIsHidden(_:using:)

    func testHideAndShowWithAnimator() {
        let view = makeView()

        let hideCompleted = startAnimator { view.setIsHidden(true, using: $0) }
        wait(for: [hideCompleted], timeout: Self.timeout)
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(view.alpha, 1)

        let showCompleted = startAnimator { view.setIsHidden(false, using: $0) }
        wait(for: [showCompleted], timeout: Self.timeout)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alpha, 1)
    }

    func testShowDuringHideAnimation() {
        let view = makeView()

        let hideCompleted = startAnimator { view.setIsHidden(true, using: $0) }
        let showCompleted = startAnimator { view.setIsHidden(false, using: $0) }
        wait(for: [hideCompleted, showCompleted], timeout: Self.timeout)

        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alpha, 1)
    }

    func testShowWithoutAnimatorDuringHideAnimation() {
        let view = makeView()

        let hideCompleted = startAnimator { view.setIsHidden(true, using: $0) }
        view.setIsHidden(false, using: nil)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alpha, 1)

        wait(for: [hideCompleted], timeout: Self.timeout)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alpha, 1)
    }

    func testHideDuringShowAnimation() {
        let view = makeView()
        view.isHidden = true

        let showCompleted = startAnimator { view.setIsHidden(false, using: $0) }
        let hideCompleted = startAnimator { view.setIsHidden(true, using: $0) }
        wait(for: [showCompleted, hideCompleted], timeout: Self.timeout)

        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(view.alpha, 1)
    }

    func testHideDuringHideAnimation() {
        let view = makeView()

        // The second animator has nothing else to animate: it must still complete.
        let firstHideCompleted = startAnimator { view.setIsHidden(true, using: $0) }
        let secondHideCompleted = startAnimator { view.setIsHidden(true, using: $0) }
        wait(for: [firstHideCompleted, secondHideCompleted], timeout: Self.timeout)
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(view.alpha, 1)

        let showCompleted = startAnimator { view.setIsHidden(false, using: $0) }
        wait(for: [showCompleted], timeout: Self.timeout)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alpha, 1)
    }

    func testHideDuringHideAnimationThatIsReversed() {
        let view = makeView()
        let otherView = makeView()

        let firstHideAnimator = makeAnimator()
        view.setIsHidden(true, using: firstHideAnimator)
        let firstHideCompleted = start(firstHideAnimator)
        let secondHideCompleted = startAnimator { animator in
            view.setIsHidden(true, using: animator)
            otherView.setIsHidden(true, using: animator)
        }
        firstHideAnimator.isReversed = true
        wait(for: [firstHideCompleted, secondHideCompleted], timeout: Self.timeout)

        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(view.alpha, 1)
    }

    func testHideWithoutAnimatorDuringHideAnimation() {
        let view = makeView()

        let hideCompleted = startAnimator { view.setIsHidden(true, using: $0) }
        view.setIsHidden(true, using: nil)
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(view.alpha, 1)

        wait(for: [hideCompleted], timeout: Self.timeout)
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(view.alpha, 1)
    }

    func testShowBeforeHideAnimationStarts() {
        let view = makeView()

        let hideAnimator = makeAnimator()
        view.setIsHidden(true, using: hideAnimator)
        view.setIsHidden(false, using: nil)
        wait(for: [start(hideAnimator)], timeout: Self.timeout)

        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alpha, 1)
    }

    func testHideAfterHideAnimatorThatNeverRuns() {
        let view = makeView()

        // An animator that is never started never calls its completion handlers.
        view.setIsHidden(true, using: makeAnimator())

        let hideCompleted = startAnimator { view.setIsHidden(true, using: $0) }
        wait(for: [hideCompleted], timeout: Self.timeout)
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(view.alpha, 1)
    }

    func testShowHiddenTransparentView() {
        let view = makeView()
        view.isHidden = true
        view.alpha = 0

        let showCompleted = startAnimator { view.setIsHidden(false, using: $0) }
        wait(for: [showCompleted], timeout: Self.timeout)

        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alpha, 1)
    }

    func testAlphaChangedWithShowDuringHideAnimation() {
        let view = makeView()

        // Eg a toolbar that is also faded out while the caption is being edited.
        let hideCompleted = startAnimator { view.setIsHidden(true, using: $0) }
        let showCompleted = startAnimator { animator in
            view.setIsHidden(false, using: animator)
            animator.addAnimations { view.alpha = 0 }
        }
        wait(for: [hideCompleted, showCompleted], timeout: Self.timeout)

        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alpha, 0)
    }

    // MARK: - setIsHidden(_:animated:completion:)

    func testAnimatedHideAndShow() {
        let view = makeView()

        let hideCompleted = expectation(description: "Hide completed")
        view.setIsHidden(true, animated: true) { finished in
            XCTAssertTrue(finished)
            hideCompleted.fulfill()
        }
        wait(for: [hideCompleted], timeout: Self.timeout)
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(view.alpha, 1)

        var didCompleteRedundantHide = false
        view.setIsHidden(true, animated: true) { _ in didCompleteRedundantHide = true }
        XCTAssertTrue(didCompleteRedundantHide)

        let showCompleted = expectation(description: "Show completed")
        view.setIsHidden(false, animated: true) { finished in
            XCTAssertTrue(finished)
            showCompleted.fulfill()
        }
        wait(for: [showCompleted], timeout: Self.timeout)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alpha, 1)
    }

    func testAnimatedShowDuringAnimatedHide() {
        let view = makeView()

        let hideCompleted = expectation(description: "Hide completed")
        view.setIsHidden(true, animated: true) { _ in hideCompleted.fulfill() }
        let showCompleted = expectation(description: "Show completed")
        view.setIsHidden(false, animated: true) { _ in showCompleted.fulfill() }
        wait(for: [hideCompleted, showCompleted], timeout: Self.timeout)

        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alpha, 1)
    }

    func testShowWithoutAnimationDuringAnimatedHide() {
        let view = makeView()

        let hideCompleted = expectation(description: "Hide completed")
        view.setIsHidden(true, animated: true) { _ in hideCompleted.fulfill() }
        view.setIsHidden(false, animated: false)
        wait(for: [hideCompleted], timeout: Self.timeout)

        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alpha, 1)
    }

    // MARK: - Helpers

    private func makeView() -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        window.addSubview(view)
        return view
    }

    private func makeAnimator() -> UIViewPropertyAnimator {
        UIViewPropertyAnimator(duration: 0.1, curve: .linear)
    }

    /// Lets `configure` add animations to a new animator, then starts it.
    private func startAnimator(_ configure: (UIViewPropertyAnimator) -> Void) -> XCTestExpectation {
        let animator = makeAnimator()
        configure(animator)
        return start(animator)
    }

    /// Starts `animator`, returning an expectation that is fulfilled after its other completion handlers have run.
    private func start(_ animator: UIViewPropertyAnimator) -> XCTestExpectation {
        let completed = expectation(description: "Animator completed")
        animator.addCompletion { _ in completed.fulfill() }
        animator.startAnimation()
        return completed
    }
}
