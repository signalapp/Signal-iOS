//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;
@class LKMention;
@class LKMentionCandidateSelectionView;
@class OWSLinkPreviewDraft;
@class OWSQuotedReplyModel;
@class SignalAttachment;
@class TSThread;

@protocol ConversationInputToolbarDelegate <NSObject>

- (void)sendButtonPressed;

- (void)attachmentButtonPressed;

#pragma mark - Voice Memo

- (void)voiceMemoGestureDidStart;

- (void)voiceMemoGestureDidLock;

- (void)voiceMemoGestureDidComplete;

- (void)voiceMemoGestureDidCancel;

- (void)voiceMemoGestureDidUpdateCancelWithRatioComplete:(CGFloat)cancelAlpha;

- (void)handleMentionCandidateSelected:(LKMention *)mentionCandidate from:(LKMentionCandidateSelectionView *)mentionCandidateSelectionView;

@end

#pragma mark -

@class ConversationInputTextView;

@protocol ConversationInputTextViewDelegate;

@interface ConversationInputToolbar : UIView

- (instancetype)initWithConversationStyle:(ConversationStyle *)conversationStyle NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;

@property (nonatomic, weak) id<ConversationInputToolbarDelegate> inputToolbarDelegate;

- (void)beginEditingTextMessage;
- (void)endEditingTextMessage;
- (BOOL)isInputTextViewFirstResponder;

- (void)setInputTextViewDelegate:(id<ConversationInputTextViewDelegate>)value;

- (NSString *)messageText;
- (void)setMessageText:(NSString *_Nullable)value animated:(BOOL)isAnimated;
- (void)setPlaceholderText:(NSString *)placeholderText;
- (void)clearTextMessageAnimated:(BOOL)isAnimated;
- (void)toggleDefaultKeyboard;
- (void)setAttachmentButtonHidden:(BOOL)isHidden;

- (void)updateFontSizes;

- (void)updateLayoutWithSafeAreaInsets:(UIEdgeInsets)safeAreaInsets;
- (void)ensureTextViewHeight;

#pragma mark - Voice Memo

- (void)lockVoiceMemoUI;

- (void)showVoiceMemoUI;

- (void)hideVoiceMemoUI:(BOOL)animated;

- (void)setVoiceMemoUICancelAlpha:(CGFloat)cancelAlpha;

- (void)cancelVoiceMemoIfNecessary;

#pragma mark -

@property (nonatomic, nullable) OWSQuotedReplyModel *quotedReply;

@property (nonatomic, nullable, readonly) OWSLinkPreviewDraft *linkPreviewDraft;

- (void)hideInputMethod;

#pragma mark - Mention Candidate Selection View

- (void)showMentionCandidateSelectionViewFor:(NSArray<LKMention *> *)mentionCandidates in:(TSThread *)thread;

- (void)hideMentionCandidateSelectionView;

@end

NS_ASSUME_NONNULL_END
