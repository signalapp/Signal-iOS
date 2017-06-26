//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMessagesViewController.h>

NS_ASSUME_NONNULL_BEGIN

@protocol OWSVoiceMemoGestureDelegate <NSObject>

- (void)voiceMemoGestureDidStart;

- (void)voiceMemoGestureDidEnd;

- (void)voiceMemoGestureDidCancel;

- (void)voiceMemoGestureDidChange:(CGFloat)cancelAlpha;

@end

#pragma mark -

@protocol OWSSendMessageGestureDelegate <NSObject>

- (void)sendMessageGestureRecognized;

@end

#pragma mark -

@interface OWSMessagesToolbarContentView : JSQMessagesToolbarContentView

@property (nonatomic, nullable, weak) id<OWSVoiceMemoGestureDelegate> voiceMemoGestureDelegate;

@property (nonatomic, nullable, weak) id<OWSSendMessageGestureDelegate> sendMessageGestureDelegate;

- (void)ensureSubviews;

- (void)ensureEnabling;

- (void)cancelVoiceMemoIfNecessary;

@end

NS_ASSUME_NONNULL_END
