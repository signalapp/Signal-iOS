//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SignalAttachment;

@protocol ConversationInputToolbarDelegate <NSObject>

- (void)sendButtonPressed;

- (void)attachmentButtonPressed;

#pragma mark - Voice Memo

- (void)voiceMemoGestureDidStart;

- (void)voiceMemoGestureDidEnd;

- (void)voiceMemoGestureDidCancel;

- (void)voiceMemoGestureDidChange:(CGFloat)cancelAlpha;

#pragma mark - Attachment Approval

- (void)didApproveAttachment:(SignalAttachment *)attachment;

@end

#pragma mark -

@class ConversationInputTextView;

@protocol ConversationInputTextViewDelegate;

@interface ConversationInputToolbar : UIView

@property (nonatomic, weak) id<ConversationInputToolbarDelegate> inputToolbarDelegate;

- (void)beginEditingTextMessage;
- (void)endEditingTextMessage;
- (BOOL)isInputTextViewFirstResponder;

- (void)setInputTextViewDelegate:(id<ConversationInputTextViewDelegate>)value;

- (NSString *)messageText;
- (void)setMessageText:(NSString *_Nullable)value;
- (void)clearTextMessage;
- (void)toggleDefaultKeyboard;

- (void)updateFontSizes;

#pragma mark - Voice Memo

- (void)showVoiceMemoUI;

- (void)hideVoiceMemoUI:(BOOL)animated;

- (void)setVoiceMemoUICancelAlpha:(CGFloat)cancelAlpha;

- (void)cancelVoiceMemoIfNecessary;

#pragma mark - Attachment Approval

- (void)showApprovalUIForAttachment:(SignalAttachment *)attachment;
- (void)viewWillAppear:(BOOL)animated;
- (void)viewWillDisappear:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
