//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

//! Project version number for SignalUI.
FOUNDATION_EXPORT double SignalUIVersionNumber;

//! Project version string for SignalUI.
FOUNDATION_EXPORT const unsigned char SignalUIVersionString[];

// The public headers of the framework
#import <SignalUI/AttachmentSharing.h>
#import <SignalUI/BlockListUIUtils.h>
#import <SignalUI/CVItemViewModel.h>
#import <SignalUI/ContactsViewHelper.h>
#import <SignalUI/FingerprintViewController.h>
#import <SignalUI/FingerprintViewScanController.h>
#import <SignalUI/OWSAnyTouchGestureRecognizer.h>
#import <SignalUI/OWSAudioPlayer.h>
#import <SignalUI/OWSBezierPathView.h>
#import <SignalUI/OWSBubbleView.h>
#import <SignalUI/OWSNavigationController.h>
#import <SignalUI/OWSProfileManager+SignalUI.h>
#import <SignalUI/OWSQuotedReplyModel.h>
#import <SignalUI/OWSSearchBar.h>
#import <SignalUI/OWSTableViewController.h>
#import <SignalUI/OWSTextField.h>
#import <SignalUI/OWSTextView.h>
#import <SignalUI/RecipientPickerViewController.h>
#import <SignalUI/ScreenLockViewController.h>
#import <SignalUI/Theme.h>
#import <SignalUI/UIFont+OWS.h>
#import <SignalUI/UIUtil.h>
#import <SignalUI/UIView+SignalUI.h>
#import <SignalUI/UIViewController+OWS.h>
#import <SignalUI/UIViewController+Permissions.h>
#import <SignalUI/ViewControllerUtils.h>
