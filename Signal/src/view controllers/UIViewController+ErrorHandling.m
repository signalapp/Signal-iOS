//
//  UIViewController+ErrorHandling.m
//  Signal
//
//  Created by David Deller on 11/29/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "UIViewController+ErrorHandling.h"

@implementation UIViewController (ErrorHandling)

- (void)ows_showAlertForError:(NSError *)error {
    
    if (error == nil) {
        NSLog(@"%@: Error condition, but no NSError to display", self.class);
        return;
    } else if (error.localizedDescription.length == 0) {
        NSLog(@"%@: Unable to display error because localizedDescription was not set: %@", self.class, error);
        return;
    }
    
    NSString *alertBody = nil;
    if (error.localizedFailureReason.length > 0) {
        alertBody = error.localizedFailureReason;
    } else if (error.localizedRecoverySuggestion.length > 0) {
        alertBody = error.localizedRecoverySuggestion;
    }
    
    SignalAlertView(error.localizedDescription, alertBody);
}

@end
