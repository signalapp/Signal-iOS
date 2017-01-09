//
//  OWSMessageTextViewDelegate.h
//  Signal
//
//  Created by Adam Kunicki on 12/22/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "../view controllers/OpenInChromeController.h"
#import "../view controllers/OpenInThirdPartyBrowserControllerObjC.h"

@interface MessageTextViewDelegate : UIViewController <UITextViewDelegate>

@property (nonatomic, strong) OpenInThirdPartyBrowserControllerObjC *openInFirefox;
@property (nonatomic, strong) OpenInThirdPartyBrowserControllerObjC *openInBrave;

// Deprecated in iOS 10
- (BOOL)textView:(UITextView *)textView
    shouldInteractWithURL:(NSURL *)URL
    inRange:(NSRange)characterRange;

- (BOOL)textView:(UITextView *)textView
    shouldInteractWithURL:(NSURL *)URL
    inRange:(NSRange)characterRange
    interaction:(UITextItemInteraction)interaction;

@end
