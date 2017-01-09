//
//  OWSMessageTextViewDelegate.m
//  Signal
//
//  Created by Adam Kunicki on 12/22/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

#import "Environment.h"
#import "MessageTextViewDelegate.h"

#define kIndexSafari 0
#define kIndexGoogleChrome 1
#define kIndexFirefox 2
#define kIndexBrave 3

@implementation MessageTextViewDelegate

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange
{
    NSUInteger selectedBrowser = [Environment.preferences getOpenLinksWith];
    
    OpenInChromeController *openInChrome = [OpenInChromeController sharedInstance];
    if (self.openInFirefox == nil) {
        self.openInFirefox = [[OpenInThirdPartyBrowserControllerObjC alloc] initWithBrowser:ThirdPartyBrowserFirefox];
    }
    
    if (self.openInBrave == nil) {
        self.openInBrave = [[OpenInThirdPartyBrowserControllerObjC alloc] initWithBrowser:ThirdPartyBrowserBrave];
    }
    
    switch (selectedBrowser) {
        case kIndexGoogleChrome:
            if ([openInChrome isChromeInstalled]) {
                [openInChrome openInChrome:URL];
            }
            break;
        case kIndexFirefox:
            if ([self.openInFirefox isInstalled]) {
                [self.openInFirefox openInBrowser:URL];
            }
            break;
        case kIndexBrave:
            if ([self.openInBrave isInstalled]) {
                [self.openInBrave openInBrowser:URL];
            }
            break;
        case kIndexSafari:
        default:
            break;
    }
    
    return YES;
}

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange interaction:(UITextItemInteraction)interaction
{
    return [self textView:textView shouldInteractWithURL:URL inRange:characterRange];
}

@end
