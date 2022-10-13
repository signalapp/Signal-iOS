//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalUI/BlockListUIUtils.h>

NS_ASSUME_NONNULL_BEGIN

@class CVMediaCache;
@class ConversationInputTextView;
@class ConversationStyle;
@class MessageBody;
@class OWSLinkPreviewDraft;
@class OWSQuotedReplyModel;
@class PHAsset;
@class PhotoCapture;
@class SignalAttachment;
@class StickerInfo;
@class TSThreadReplyInfo;
@class VoiceMessageModel;

@protocol ConversationInputTextViewDelegate;
@protocol MentionTextViewDelegate;

@protocol ConversationInputToolbarDelegate <NSObject>

- (void)sendButtonPressed;

- (void)sendSticker:(StickerInfo *)stickerInfo;

- (void)presentManageStickersView;

- (void)updateToolbarHeight;

#pragma mark - Voice Memo

- (void)voiceMemoGestureDidStart;

- (void)voiceMemoGestureDidLock;

- (void)voiceMemoGestureDidComplete;

- (void)voiceMemoGestureDidCancel;

- (void)voiceMemoGestureWasInterrupted;

- (void)sendVoiceMemoDraft:(VoiceMessageModel *)voiceMemoDraft;

#pragma mark - Attachments

- (void)cameraButtonPressed;

- (void)galleryButtonPressed;

- (void)gifButtonPressed;

- (void)fileButtonPressed;

- (void)contactButtonPressed;

- (void)locationButtonPressed;

- (void)paymentButtonPressed;

- (void)didSelectRecentPhotoWithAsset:(PHAsset *)asset
                           attachment:(SignalAttachment *)attachment
    NS_SWIFT_NAME(didSelectRecentPhoto(asset:attachment:));

- (void)showUnblockConversationUI:(nullable BlockActionCompletionBlock)completion
    NS_SWIFT_NAME(showUnblockConversationUI(completion:));

- (BOOL)isBlockedConversation;

- (BOOL)isGroup;

@end

#pragma mark -

@interface ConversationInputToolbar : UIView

@property (nonatomic) BOOL isMeasuringKeyboardHeight;

- (instancetype)initWithConversationStyle:(ConversationStyle *)conversationStyle
                               mediaCache:(CVMediaCache *)mediaCache
                             messageDraft:(nullable MessageBody *)messageDraft
                              quotedReply:(nullable OWSQuotedReplyModel *)quotedReply
                     inputToolbarDelegate:(id<ConversationInputToolbarDelegate>)inputToolbarDelegate
                    inputTextViewDelegate:(id<ConversationInputTextViewDelegate>)inputTextViewDelegate
                          mentionDelegate:(id<MentionTextViewDelegate>)mentionDelegate NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;

- (void)beginEditingMessage;
- (void)endEditingMessage;
- (BOOL)isInputViewFirstResponder;

- (nullable MessageBody *)messageBody;
- (nullable TSThreadReplyInfo *)draftReply;
- (void)setMessageBody:(nullable MessageBody *)value animated:(BOOL)isAnimated;
- (void)acceptAutocorrectSuggestion;
- (void)clearTextMessageAnimated:(BOOL)isAnimated;
- (void)clearDesiredKeyboard;
- (void)showStickerKeyboard;
- (void)showAttachmentKeyboard;

- (void)updateFontSizes;

/// Returns true if changes were applied
- (BOOL)updateLayoutWithSafeAreaInsets:(UIEdgeInsets)safeAreaInsets;
- (void)ensureTextViewHeight;

- (void)viewDidAppear;

- (void)ensureFirstResponderState;

#pragma mark - Voice Memo

- (void)lockVoiceMemoUI;

- (void)showVoiceMemoUI;

- (void)showVoiceMemoDraft:(VoiceMessageModel *)voiceMemoDraft;

- (void)hideVoiceMemoUI:(BOOL)animated;

- (void)showVoiceMemoTooltip;

- (void)removeVoiceMemoTooltip;

@property (nonatomic, nullable, readonly) VoiceMessageModel *voiceMemoDraft;

#pragma mark -

@property (nonatomic, nullable) OWSQuotedReplyModel *quotedReply;
@property (nonatomic, assign, readonly) BOOL isAnimatingQuotedReply;
+ (NSTimeInterval)quotedReplyAnimationDuration;

@property (nonatomic, nullable, readonly) OWSLinkPreviewDraft *linkPreviewDraft;

- (void)updateConversationStyle:(ConversationStyle *)conversationStyle NS_SWIFT_NAME(update(conversationStyle:));

@end

NS_ASSUME_NONNULL_END
