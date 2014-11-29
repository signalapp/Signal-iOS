//
//  UIViewController+ErrorHandling.h
//  Signal
//
//  Created by David Deller on 11/29/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIViewController (ErrorHandling)

- (void)ows_showAlertForError:(NSError *)error;

@end
