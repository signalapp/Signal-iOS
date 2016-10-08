//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//  Created by Michael Kirk on 3/11/16.

@class TSInteraction;

NS_ASSUME_NONNULL_BEGIN

@protocol OWSMessageEditing <NSObject>

- (BOOL)canPerformEditingAction:(SEL)action;
- (void)performEditingAction:(SEL)action;

@end

NS_ASSUME_NONNULL_END
