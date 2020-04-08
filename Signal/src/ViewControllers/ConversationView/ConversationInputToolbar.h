//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/BlockListUIUtils.h>

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;
@class OWSLinkPreviewDraft;
@class OWSQuotedReplyModel;
@class PHAsset;
@class PhotoCapture;
@class SignalAttachment;
@class StickerInfo;

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

- (void)voiceMemoGestureDidUpdateCancelWithRatioComplete:(CGFloat)cancelAlpha;

#pragma mark - Attachments

- (void)cameraButtonPressed;

- (void)cameraButtonPressedWithPhotoCapture:(nullable PhotoCapture *)photoCapture;

- (void)galleryButtonPressed;

- (void)gifButtonPressed;

- (void)fileButtonPressed;

- (void)contactButtonPressed;

- (void)locationButtonPressed;

- (void)didSelectRecentPhotoWithAsset:(PHAsset *)asset attachment:(SignalAttachment *)attachment;

- (void)showUnblockConversationUI:(nullable BlockActionCompletionBlock)completionBlock;

- (BOOL)isBlockedConversation;

@end

#pragma mark -

@class ConversationInputTextView;

@protocol ConversationInputTextViewDelegate;

@interface ConversationInputToolbar : UIView

- (instancetype)initWithConversationStyle:(ConversationStyle *)conversationStyle NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;

@property (nonatomic, weak) id<ConversationInputToolbarDelegate> inputToolbarDelegate;

- (void)beginEditingMessage;
- (void)endEditingMessage;
- (BOOL)isInputViewFirstResponder;

- (void)setInputTextViewDelegate:(id<ConversationInputTextViewDelegate>)value;

- (NSString *)messageText;
- (void)setMessageText:(NSString *_Nullable)value animated:(BOOL)isAnimated;
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

- (void)hideVoiceMemoUI:(BOOL)animated;

- (void)setVoiceMemoUICancelAlpha:(CGFloat)cancelAlpha;

- (void)cancelVoiceMemoIfNecessary;

#pragma mark -

@property (nonatomic, nullable) OWSQuotedReplyModel *quotedReply;

@property (nonatomic, nullable, readonly) OWSLinkPreviewDraft *linkPreviewDraft;

@end

NS_ASSUME_NONNULL_END
