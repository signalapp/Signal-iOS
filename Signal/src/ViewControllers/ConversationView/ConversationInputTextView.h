//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SignalAttachment;

@protocol ConversationInputTextViewDelegate <NSObject>

- (void)didPasteAttachment:(SignalAttachment *_Nullable)attachment;

- (void)inputTextViewDidBecomeFirstResponder;

@end

#pragma mark -

@protocol ConversationTextViewToolbarDelegate <NSObject>

- (void)textViewDidChange;

- (void)textViewReturnPressed;

@end

#pragma mark -

@interface ConversationInputTextView : UITextView

@property (weak, nonatomic) id<ConversationInputTextViewDelegate> inputTextViewDelegate;

@property (weak, nonatomic) id<ConversationTextViewToolbarDelegate> textViewToolbarDelegate;

- (NSString *)trimmedText;

@end

NS_ASSUME_NONNULL_END
