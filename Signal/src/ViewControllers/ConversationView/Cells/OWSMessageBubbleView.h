//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class ContactShareViewModel;
@class ConversationStyle;

@protocol ConversationViewItem;

@class OWSContact;
@class OWSLinkPreview;
@class OWSQuotedReplyModel;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSOutgoingMessage;

typedef NS_ENUM(NSUInteger, OWSMessageGestureLocation) {
    // Message text, etc.
    OWSMessageGestureLocation_Default,
    OWSMessageGestureLocation_OversizeText,
    OWSMessageGestureLocation_Media,
    OWSMessageGestureLocation_QuotedReply,
    OWSMessageGestureLocation_LinkPreview,
};

extern const UIDataDetectorTypes kOWSAllowedDataDetectorTypes;

@protocol OWSMessageBubbleViewDelegate

- (void)didTapImageViewItem:(id<ConversationViewItem>)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIView *)imageView;

- (void)didTapVideoViewItem:(id<ConversationViewItem>)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIView *)imageView;

- (void)didTapAudioViewItem:(id<ConversationViewItem>)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream;

- (void)didTapTruncatedTextMessage:(id<ConversationViewItem>)conversationItem;

- (void)didTapFailedIncomingAttachment:(id<ConversationViewItem>)viewItem;

- (void)didTapConversationItem:(id<ConversationViewItem>)viewItem quotedReply:(OWSQuotedReplyModel *)quotedReply;
- (void)didTapConversationItem:(id<ConversationViewItem>)viewItem
                                 quotedReply:(OWSQuotedReplyModel *)quotedReply
    failedThumbnailDownloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer;

- (void)didTapConversationItem:(id<ConversationViewItem>)viewItem linkPreview:(OWSLinkPreview *)linkPreview;

- (void)didTapContactShareViewItem:(id<ConversationViewItem>)viewItem;

- (void)didTapSendMessageToContactShare:(ContactShareViewModel *)contactShare
    NS_SWIFT_NAME(didTapSendMessage(toContactShare:));
- (void)didTapSendInviteToContactShare:(ContactShareViewModel *)contactShare
    NS_SWIFT_NAME(didTapSendInvite(toContactShare:));
- (void)didTapShowAddToContactUIForContactShare:(ContactShareViewModel *)contactShare
    NS_SWIFT_NAME(didTapShowAddToContactUI(forContactShare:));

@property (nonatomic, readonly, nullable) NSString *lastSearchedText;

@end

#pragma mark -

@interface OWSMessageBubbleView : UIView

@property (nonatomic, nullable) id<ConversationViewItem> viewItem;

@property (nonatomic) ConversationStyle *conversationStyle;

@property (nonatomic) NSCache *cellMediaCache;

@property (nonatomic, nullable, readonly) UIView *bodyMediaView;

@property (nonatomic, weak) id<OWSMessageBubbleViewDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)configureViews;

- (void)loadContent;
- (void)unloadContent;

- (CGSize)measureSize;

- (void)prepareForReuse;

+ (NSDictionary *)senderNamePrimaryAttributes;
+ (NSDictionary *)senderNameSecondaryAttributes;

#pragma mark - Gestures

- (OWSMessageGestureLocation)gestureLocationForLocation:(CGPoint)locationInMessageBubble;

// This only needs to be called when we use the cell _outside_ the context
// of a conversation view message cell.
- (void)addTapGestureHandler;

- (void)handleTapGesture:(UITapGestureRecognizer *)sender;

@end

NS_ASSUME_NONNULL_END
