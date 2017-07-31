//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSViewController.h"

@class TSThread;

NS_ASSUME_NONNULL_BEGIN

@protocol SelectThreadViewControllerDelegate <NSObject>

- (void)threadWasSelected:(TSThread *)thread;

- (BOOL)canSelectBlockedContact;

- (nullable UIView *)createHeaderWithSearchBar:(UISearchBar *)searchBar;

@end

#pragma mark -

// A base class for views used to pick a single signal user, either by
// entering a phone number or picking from your contacts.
@interface SelectThreadViewController : OWSViewController

@property (nonatomic, weak) id<SelectThreadViewControllerDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
