//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMessagesViewController.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessagesInputToolbar : JSQMessagesInputToolbar

- (void)showVoiceMemoUI;

- (void)hideVoiceMemoUI:(BOOL)animated;

- (void)setVoiceMemoUICancelAlpha:(CGFloat)cancelAlpha;

@end

NS_ASSUME_NONNULL_END
