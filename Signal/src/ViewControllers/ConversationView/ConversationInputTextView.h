//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

//#import <JSQMessagesViewController/JSQMessagesViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalAttachment;

@protocol ConversationInputTextViewDelegate <NSObject>

- (void)didPasteAttachment:(SignalAttachment *_Nullable)attachment;

- (void)textViewDidChangeLayout;

- (void)inputTextViewDidBecomeFirstResponder;

@end

#pragma mark -

@interface ConversationInputTextView : UITextView

@property (weak, nonatomic) id<ConversationInputTextViewDelegate> inputTextViewDelegate;

- (NSString *)trimmedText;

@end

NS_ASSUME_NONNULL_END
