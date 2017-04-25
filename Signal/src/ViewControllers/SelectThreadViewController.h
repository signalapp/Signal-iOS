//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@class TSThread;

@protocol SelectThreadViewControllerDelegate <NSObject>

- (void)threadWasSelected:(TSThread *)thread;

- (BOOL)canSelectBlockedContact;

@end

#pragma mark -

@interface SelectThreadViewController : UIViewController

@property (nonatomic, weak) id<SelectThreadViewControllerDelegate> delegate;

@end
