//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/BlockListUIUtils.h>

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;
@class MessageBody;
@class OWSLinkPreviewDraft;
@class OWSQuotedReplyModel;
@class PHAsset;
@class PhotoCapture;
@class SignalAttachment;
@class StickerInfo;
@class VoiceMessageModel;

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

@class ConversationInputTextView;

@protocol ConversationInputTextViewDelegate;

@interface ConversationInputToolbar : UIView

@property (nonatomic) BOOL isMeasuringKeyboardHeight;

- (instancetype)initWithConversationStyle:(ConversationStyle *)conversationStyle
                             messageDraft:(nullable MessageBody *)messageDraft
                     inputToolbarDelegate:(id<ConversationInputToolbarDelegate>)inputToolbarDelegate
                    inputTextViewDelegate:(id<ConversationInputTextViewDelegate>)inputTextViewDelegate
                          mentionDelegate:(id<MentionTextViewDelegate>)mentionDelegate NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;

- (void)beginEditingMessage;
- (void)endEditingMessage;
- (BOOL)isInputViewFirstResponder;

- (nullable MessageBody *)messageBody;
- (void)setMessageBody:(nullable MessageBody *)value animated:(BOOL)isAnimated;
- (void)acceptAutocorrectSuggestion;
- (void)clearTextMessageAnimated:(BOOL)isAnimated;
- (void)clearDesiredKeyboard;
- (void)toggleDefaultKeyboard;
- (void)showStickerKeyboard;
- (void)showAttachmentKeyboard;

- (void)updateFontSizes;

- (void)updateLayoutWithSafeAreaInsets:(UIEdgeInsets)safeAreaInsets;
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

@property (nonatomic, nullable, readonly) OWSLinkPreviewDraft *linkPreviewDraft;

- (void)updateConversationStyle:(ConversationStyle *)conversationStyle NS_SWIFT_NAME(update(conversationStyle:));

@end

NS_ASSUME_NONNULL_END
