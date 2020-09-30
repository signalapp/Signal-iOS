//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "CNContactViewController+OWS.h"

@import ObjectiveC.runtime;

@implementation CNContactViewController (iOS13BugFix)

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];

        // On iOS 13 hitting "cancel" on the CNContactViewController
        // presents the discard action sheet behind the keyboard.
        // We swizzle the cancel callback and force the keyboard to
        // dismiss.
        if (@available(iOS 14, *)) {
            // do nothing
        } else if (@available(iOS 13, *)) {
            SEL originalSelector = NSSelectorFromString(@"editCancel:");
            SEL swizzledSelector = @selector(ows_editCancel:);

            Method originalMethod = class_getInstanceMethod(class, originalSelector);
            Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

- (void)ows_editCancel:(UIBarButtonItem *)sender
{
    [UIApplication.sharedApplication sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
    [self ows_editCancel:sender];
}

@end
