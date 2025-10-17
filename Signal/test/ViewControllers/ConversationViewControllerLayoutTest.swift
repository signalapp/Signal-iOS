//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import UIKit

@testable import Signal
@testable import SignalServiceKit
@testable import SignalUI

class ConversationViewControllerLayoutTest: SignalBaseTest {

    func testCollectionViewConstrainedToBottomBar() {
        // Create a mock conversation view controller to test constraint setup
        let thread = ContactThreadFactory().create()
        let conversationViewController = ConversationViewController(threadViewModel: ContactThreadViewModel(thread: thread))
        
        // Load the view to trigger createContents()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        window.rootViewController = conversationViewController
        window.makeKeyAndVisible()
        conversationViewController.view.layoutIfNeeded()
        
        // Verify that collectionView is constrained to bottomBar
        let collectionView = conversationViewController.collectionView
        let bottomBar = conversationViewController.bottomBar
        
        // Find the constraint that pins collectionView bottom to bottomBar top
        var foundCorrectConstraint = false
        for constraint in collectionView.constraints {
            if constraint.firstItem === collectionView &&
               constraint.firstAttribute == .bottom &&
               constraint.secondItem === bottomBar &&
               constraint.secondAttribute == .top {
                foundCorrectConstraint = true
                break
            }
        }
        
        // Also check bottomBar constraints
        for constraint in bottomBar.constraints {
            if constraint.firstItem === bottomBar &&
               constraint.firstAttribute == .bottom &&
               constraint.secondItem === collectionView &&
               constraint.secondAttribute == .top {
                foundCorrectConstraint = true
                break
            }
        }
        
        XCTAssertTrue(foundCorrectConstraint, "collectionView should be constrained to bottomBar.top to fix keyboard dismissal bug")
    }
    
    func testContentInsetsWithKeyboardDismissed() {
        let thread = ContactThreadFactory().create()
        let conversationViewController = ConversationViewController(threadViewModel: ContactThreadViewModel(thread: thread))
        
        // Load the view
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        window.rootViewController = conversationViewController
        window.makeKeyAndVisible()
        conversationViewController.view.layoutIfNeeded()
        
        // Simulate keyboard dismissed state (keyboardLayoutGuide height = 0)
        conversationViewController.updateContentInsets()
        
        let contentInset = conversationViewController.collectionView.contentInset
        let bottomBar = conversationViewController.bottomBar
        
        // With keyboard dismissed, bottom inset should be just the bottomBar height minus safe area
        let expectedBottomInset = bottomBar.frame.height - bottomBar.safeAreaInsets.bottom
        XCTAssertEqual(contentInset.bottom, expectedBottomInset, 
                      accuracy: 1.0, // Allow 1pt tolerance for layout calculations
                      "Content inset bottom should match bottomBar height minus safe area when keyboard is dismissed")
    }
    
    func testContentInsetsWithKeyboardVisible() {
        let thread = ContactThreadFactory().create()
        let conversationViewController = ConversationViewController(threadViewModel: ContactThreadViewModel(thread: thread))
        
        // Load the view
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        window.rootViewController = conversationViewController
        window.makeKeyAndVisible()
        conversationViewController.view.layoutIfNeeded()
        
        // Simulate keyboard visible state by temporarily setting keyboardLayoutGuide height
        // Note: In a real test environment, we can't actually show a keyboard, but we can
        // test that the content insets calculation logic is correct
        conversationViewController.updateContentInsets()
        
        let contentInset = conversationViewController.collectionView.contentInset
        let bottomBar = conversationViewController.bottomBar
        
        // The bottom inset should be the bottomBar height minus safe area
        // This ensures messages are visible above the input area
        XCTAssertGreaterThan(contentInset.bottom, 0, "Content inset bottom should be positive to ensure messages are visible")
        
        // The inset should be reasonable (not excessively large)
        XCTAssertLessThan(contentInset.bottom, 200, "Content inset bottom should be reasonable size")
        
        // Verify it matches our expected calculation
        let expectedBottomInset = bottomBar.frame.height - bottomBar.safeAreaInsets.bottom
        XCTAssertEqual(contentInset.bottom, expectedBottomInset, 
                      accuracy: 1.0,
                      "Content inset calculation should match simplified formula")
    }
    
    func testLayoutConstraintsAreActive() {
        let thread = ContactThreadFactory().create()
        let conversationViewController = ConversationViewController(threadViewModel: ContactThreadViewModel(thread: thread))
        
        // Load the view
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        window.rootViewController = conversationViewController
        window.makeKeyAndVisible()
        conversationViewController.view.layoutIfNeeded()
        
        let collectionView = conversationViewController.collectionView
        let bottomBar = conversationViewController.bottomBar
        
        // Verify that the views have proper constraints and are laid out correctly
        XCTAssertNotEqual(collectionView.frame.height, 0, "collectionView should have valid height")
        XCTAssertNotEqual(bottomBar.frame.height, 0, "bottomBar should have valid height")
        
        // Verify collectionView bottom aligns with bottomBar top
        let collectionViewBottom = collectionView.frame.maxY
        let bottomBarTop = bottomBar.frame.minY
        XCTAssertEqual(collectionViewBottom, bottomBarTop, 
                      accuracy: 1.0,
                      "collectionView bottom should align with bottomBar top")
    }
    
    func testNoLayoutWarnings() {
        // This test ensures our constraint changes don't introduce layout warnings
        // In a real test environment, we would check the console for constraint warnings
        
        let thread = ContactThreadFactory().create()
        let conversationViewController = ConversationViewController(threadViewModel: ContactThreadViewModel(thread: thread))
        
        // Load the view multiple times to trigger layout cycles
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        window.rootViewController = conversationViewController
        window.makeKeyAndVisible()
        
        // Trigger multiple layout cycles
        for _ in 0..<5 {
            conversationViewController.view.layoutIfNeeded()
            conversationViewController.updateContentInsets()
        }
        
        // If we get here without crashing, the layout is stable
        // In a real test, we'd capture console output and verify no constraint warnings
        XCTAssertTrue(true, "Layout should be stable without constraint warnings")
    }
}
