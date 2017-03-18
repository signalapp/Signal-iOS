//
//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

#import "BrowserUtil.h"
#import "Environment.h"
#import "PropertyListPreferences.h"
#import "OWSMessageViewCellDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSMessageViewCellDelegate


- (BOOL)textView:(UITextView *)textView
        shouldInteractWithURL:(NSURL *)URL
        inRange:(NSRange)characterRange
        interaction:(UITextItemInteraction)interaction {
    if (interaction != UITextItemInteractionInvokeDefaultAction) {
        return YES;
    }

    PropertyListPreferences *prefs = Environment.preferences;
    NSString *defaultBrowser = [prefs defaultBrowser];
    if ([defaultBrowser isEqualToString:@"Safari"]) {
        return YES;
    }

    NSString *oldScheme = [URL.scheme lowercaseString];
    NSString *newScheme = [BrowserUtil schemesForBrowser:defaultBrowser][oldScheme];
    if (newScheme == nil) {
        return YES;
    }

    NSString *oldURLString = [URL absoluteString];
    NSURL *newURL = [NSURL URLWithString:
                     [newScheme stringByAppendingString:
                      [oldURLString substringFromIndex:
                       [oldURLString rangeOfString:@":"].location]]];
    [[UIApplication sharedApplication] openURL:newURL];
    return NO;
}

@end

NS_ASSUME_NONNULL_END
