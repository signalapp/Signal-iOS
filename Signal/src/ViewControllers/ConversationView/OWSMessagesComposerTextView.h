//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMessagesViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalAttachment;

@protocol OWSTextViewPasteDelegate <NSObject>

- (void)didPasteAttachment:(SignalAttachment *_Nullable)attachment;

- (void)textViewDidChangeSize;

@end

#pragma mark -

@interface OWSMessagesComposerTextView : JSQMessagesComposerTextView

@property (weak, nonatomic) id<OWSTextViewPasteDelegate> textViewPasteDelegate;

@end

NS_ASSUME_NONNULL_END
