//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageCell.h"
#import "OWSContactAvatarBuilder.h"
#import "OWSExpirationTimerView.h"
#import "OWSMessageBubbleView.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageCell ()

// The nullable properties are created as needed.
// The non-nullable properties are so frequently used that it's easier
// to always keep one around.

// The cell's contentView contains:
//
// * MessageView (message)
// * dateHeaderLabel (above message)
// * footerView (below message)

@property (nonatomic) OWSMessageBubbleView *messageBubbleView;
@property (nonatomic) UILabel *dateHeaderLabel;
@property (nonatomic) UIView *footerView;
@property (nonatomic) AvatarImageView *avatarView;
@property (nonatomic) UILabel *footerLabel;
@property (nonatomic, nullable) OWSExpirationTimerView *expirationTimerView;

@property (nonatomic, nullable) NSMutableArray<NSLayoutConstraint *> *viewConstraints;
@property (nonatomic) BOOL isPresentingMenuController;

@end

@implementation OWSMessageCell

// `[UIView init]` invokes `[self initWithFrame:...]`.
- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self commontInit];
    }

    return self;
}

- (void)commontInit
{
    // Ensure only called once.
    OWSAssert(!self.messageBubbleView);

    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;

    _viewConstraints = [NSMutableArray new];

    self.messageBubbleView = [OWSMessageBubbleView new];
    [self.contentView addSubview:self.messageBubbleView];

    self.footerView = [UIView containerView];
    [self.contentView addSubview:self.footerView];

    self.dateHeaderLabel = [UILabel new];
    self.dateHeaderLabel.font = self.dateHeaderDateFont;
    self.dateHeaderLabel.textAlignment = NSTextAlignmentCenter;
    self.dateHeaderLabel.textColor = [UIColor lightGrayColor];
    [self.contentView addSubview:self.dateHeaderLabel];

    self.footerLabel = [UILabel new];
    self.footerLabel.font = UIFont.ows_dynamicTypeCaption2Font;
    self.footerLabel.textColor = [UIColor lightGrayColor];
    [self.footerView addSubview:self.footerLabel];

    self.avatarView = [[AvatarImageView alloc] init];
    [self.contentView addSubview:self.avatarView];
    [self.avatarView autoSetDimension:ALDimensionWidth toSize:self.avatarSize];
    [self.avatarView autoSetDimension:ALDimensionHeight toSize:self.avatarSize];

    // Hide these views by default.
    self.dateHeaderLabel.hidden = YES;
    self.footerLabel.hidden = YES;
    self.avatarView.hidden = YES;

    [self.messageBubbleView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.dateHeaderLabel];

    [self.footerView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    self.contentView.userInteractionEnabled = YES;

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    [self addGestureRecognizer:tap];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    [self.contentView addGestureRecognizer:longPress];

    PanDirectionGestureRecognizer *panGesture = [[PanDirectionGestureRecognizer alloc]
        initWithDirection:(self.isRTL ? PanDirectionLeft : PanDirectionRight)target:self
                   action:@selector(handlePanGesture:)];
    [self addGestureRecognizer:panGesture];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setLayoutInfo:(nullable ConversationLayoutInfo *)layoutInfo
{
    [super setLayoutInfo:layoutInfo];

    self.messageBubbleView.layoutInfo = layoutInfo;
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

#pragma mark - Convenience Accessors

- (OWSMessageCellType)cellType
{
    return self.viewItem.messageCellType;
}

- (TSMessage *)message
{
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    return (TSMessage *)self.viewItem.interaction;
}

- (BOOL)isIncoming
{
    return self.viewItem.interaction.interactionType == OWSInteractionType_IncomingMessage;
}

- (BOOL)isOutgoing
{
    return self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage;
}

#pragma mark - Load

- (void)loadForDisplayWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(self.layoutInfo);
    OWSAssert(self.viewItem);
    OWSAssert(self.viewItem.interaction);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);
    OWSAssert(self.messageBubbleView);

    self.messageBubbleView.viewItem = self.viewItem;
    self.messageBubbleView.cellMediaCache = self.delegate.cellMediaCache;
    [self.messageBubbleView configureViews];
    [self.messageBubbleView loadContent];

    // Update label fonts to honor dynamic type size.
    self.dateHeaderLabel.font = self.dateHeaderDateFont;
    self.footerLabel.font = UIFont.ows_dynamicTypeCaption2Font;

    if (self.isIncoming) {
        [self.viewConstraints addObjectsFromArray:@[
            [self.messageBubbleView autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:self.layoutInfo.gutterLeading],
            [self.messageBubbleView autoPinEdgeToSuperviewEdge:ALEdgeTrailing
                                                     withInset:self.layoutInfo.gutterTrailing
                                                      relation:NSLayoutRelationGreaterThanOrEqual],
        ]];
    } else {
        [self.viewConstraints addObjectsFromArray:@[
            [self.messageBubbleView autoPinEdgeToSuperviewEdge:ALEdgeLeading
                                                     withInset:self.layoutInfo.gutterLeading
                                                      relation:NSLayoutRelationGreaterThanOrEqual],
            [self.messageBubbleView autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:self.layoutInfo.gutterTrailing],
        ]];
    }

    [self updateDateHeader];
    [self updateFooter];

    if ([self updateAvatarView]) {
        CGFloat avatarBottomMargin = round(self.layoutInfo.lastTextLineAxis - self.avatarSize * 0.5f);
        [self.viewConstraints addObjectsFromArray:@[
            // V-align the "group sender" avatar with the
            // last line of the text (if any, or where it
            // would be).
            [self.messageBubbleView autoPinLeadingToTrailingEdgeOfView:self.avatarView offset:8],
            [self.messageBubbleView autoPinEdge:ALEdgeBottom
                                         toEdge:ALEdgeBottom
                                         ofView:self.avatarView
                                     withOffset:avatarBottomMargin],
        ]];
        [self.messageBubbleView logFrameLaterWithLabel:@"messageBubbleView"];
        [self.avatarView logFrameLaterWithLabel:@"avatarView"];
    }
}

// * If cell is visible, lazy-load (expensive) view contents.
// * If cell is not visible, eagerly unload view contents.
- (void)ensureMediaLoadState
{
    OWSAssert(self.messageBubbleView);

    if (!self.isCellVisible) {
        [self.messageBubbleView unloadContent];
    } else {
        [self.messageBubbleView loadContent];
    }
}

- (void)updateDateHeader
{
    OWSAssert(self.layoutInfo);

    static NSDateFormatter *dateHeaderDateFormatter = nil;
    static NSDateFormatter *dateHeaderTimeFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateHeaderDateFormatter = [NSDateFormatter new];
        [dateHeaderDateFormatter setLocale:[NSLocale currentLocale]];
        [dateHeaderDateFormatter setDoesRelativeDateFormatting:YES];
        [dateHeaderDateFormatter setDateStyle:NSDateFormatterMediumStyle];
        [dateHeaderDateFormatter setTimeStyle:NSDateFormatterNoStyle];
        
        dateHeaderTimeFormatter = [NSDateFormatter new];
        [dateHeaderTimeFormatter setLocale:[NSLocale currentLocale]];
        [dateHeaderTimeFormatter setDoesRelativeDateFormatting:YES];
        [dateHeaderTimeFormatter setDateStyle:NSDateFormatterNoStyle];
        [dateHeaderTimeFormatter setTimeStyle:NSDateFormatterShortStyle];
    });

    if (self.viewItem.shouldShowDate) {
        NSDate *date = self.viewItem.interaction.dateForSorting;
        NSString *dateString = [dateHeaderDateFormatter stringFromDate:date];
        NSString *timeString = [dateHeaderTimeFormatter stringFromDate:date];

        NSAttributedString *attributedText = [NSAttributedString new];
        attributedText = [attributedText rtlSafeAppend:dateString
                                            attributes:@{
                                                NSFontAttributeName : self.dateHeaderDateFont,
                                                NSForegroundColorAttributeName : [UIColor lightGrayColor],
                                            }
                                         referenceView:self];
        attributedText = [attributedText rtlSafeAppend:@" "
                                            attributes:@{
                                                NSFontAttributeName : self.dateHeaderDateFont,
                                            }
                                         referenceView:self];
        attributedText = [attributedText rtlSafeAppend:timeString
                                            attributes:@{
                                                NSFontAttributeName : self.dateHeaderTimeFont,
                                                NSForegroundColorAttributeName : [UIColor lightGrayColor],
                                            }
                                         referenceView:self];

        self.dateHeaderLabel.attributedText = attributedText;
        self.dateHeaderLabel.hidden = NO;

        [self.viewConstraints addObjectsFromArray:@[
            // TODO: Are data headers symmetric or are they asymmetric? gutters are asymmetric?
            [self.dateHeaderLabel autoPinLeadingToSuperviewMarginWithInset:self.layoutInfo.gutterLeading],
            [self.dateHeaderLabel autoPinTrailingToSuperviewMarginWithInset:self.layoutInfo.gutterTrailing],
            [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeTop],
            [self.dateHeaderLabel autoSetDimension:ALDimensionHeight toSize:self.dateHeaderHeight],
        ]];
    } else {
        self.dateHeaderLabel.hidden = YES;
        [self.viewConstraints addObjectsFromArray:@[
            [self.dateHeaderLabel autoSetDimension:ALDimensionHeight toSize:0],
            [self.dateHeaderLabel autoPinEdgeToSuperviewEdge:ALEdgeTop],
        ]];
    }
}

- (BOOL)shouldShowFooter
{
    BOOL shouldShowFooter = NO;

    if (self.message.shouldStartExpireTimer) {
        shouldShowFooter = YES;
    } else if (self.isOutgoing) {
        shouldShowFooter = !self.viewItem.shouldHideRecipientStatus;
    } else if (self.viewItem.isGroupThread) {
        shouldShowFooter = YES;
    } else {
        shouldShowFooter = NO;
    }

    return shouldShowFooter;
}

- (CGFloat)footerHeight
{
    if (!self.shouldShowFooter) {
        return 0.f;
    }

    return ceil(MAX(kExpirationTimerViewSize, self.footerLabel.font.lineHeight));
}

- (CGFloat)footerVSpacing
{
    return 0.f;
}

- (void)updateFooter
{
    OWSAssert(self.layoutInfo);
    OWSAssert(self.viewItem.interaction.interactionType == OWSInteractionType_IncomingMessage
        || self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage);

    TSMessage *message = self.message;
    BOOL hasExpirationTimer = message.shouldStartExpireTimer;
    NSAttributedString *attributedText = nil;
    if (self.isOutgoing) {
        if (!self.viewItem.shouldHideRecipientStatus || hasExpirationTimer) {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)message;
            NSString *statusMessage =
                [MessageRecipientStatusUtils receiptMessageWithOutgoingMessage:outgoingMessage referenceView:self];
            attributedText = [[NSAttributedString alloc] initWithString:statusMessage attributes:@{}];
        }
    } else if (self.viewItem.isGroupThread) {
        TSIncomingMessage *incomingMessage = (TSIncomingMessage *)self.viewItem.interaction;
        attributedText = [self.delegate attributedContactOrProfileNameForPhoneIdentifier:incomingMessage.authorId];
    }
    
    if (!hasExpirationTimer &&
        !attributedText) {
        self.footerLabel.hidden = YES;
        [self.viewConstraints addObjectsFromArray:@[
            [self.footerView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.messageBubbleView],
            [self.footerView autoSetDimension:ALDimensionHeight toSize:0],
        ]];
        return;
    }

    [self.viewConstraints addObjectsFromArray:@[
        (self.isIncoming ? [self.footerView autoPinLeadingToSuperviewMarginWithInset:self.layoutInfo.gutterLeading]
                         : [self.footerView autoPinTrailingToSuperviewMarginWithInset:self.layoutInfo.gutterTrailing]),
    ]];

    [self.viewConstraints addObject:[self.footerView autoPinEdge:ALEdgeTop
                                                          toEdge:ALEdgeBottom
                                                          ofView:self.messageBubbleView
                                                      withOffset:self.footerVSpacing]];

    if (hasExpirationTimer) {
        uint64_t expirationTimestamp = message.expiresAt;
        uint32_t expiresInSeconds = message.expiresInSeconds;
        self.expirationTimerView = [[OWSExpirationTimerView alloc] initWithExpiration:expirationTimestamp
                                                               initialDurationSeconds:expiresInSeconds];
        [self.footerView addSubview:self.expirationTimerView];
    }
    if (attributedText) {
        self.footerLabel.attributedText = attributedText;
        self.footerLabel.hidden = NO;
    }

    // Footer labels can extend past the message bubble, but
    // we want to leave spaces for an expiration timer and
    // include padding so that they still visually "cling" to the
    // appropriate incoming/outgoing edge.
    const CGFloat maxFooterLabelWidth = self.layoutInfo.maxFooterWidth;
    if (hasExpirationTimer &&
        attributedText) {
        [self.viewConstraints addObjectsFromArray:@[
            [self.expirationTimerView autoVCenterInSuperview],
            [self.footerLabel autoVCenterInSuperview],
            (self.isIncoming ? [self.expirationTimerView autoPinLeadingToSuperviewMargin]
                             : [self.expirationTimerView autoPinTrailingToSuperviewMargin]),
            (self.isIncoming ? [self.footerLabel autoPinLeadingToTrailingEdgeOfView:self.expirationTimerView]
                             : [self.footerLabel autoPinTrailingToLeadingEdgeOfView:self.expirationTimerView]),
            [self.footerLabel autoSetDimension:ALDimensionWidth
                                        toSize:maxFooterLabelWidth
                                      relation:NSLayoutRelationLessThanOrEqual],
            [self.footerView autoSetDimension:ALDimensionHeight toSize:self.footerHeight],
        ]];
    } else if (hasExpirationTimer) {
        [self.viewConstraints addObjectsFromArray:@[
            [self.expirationTimerView autoVCenterInSuperview],
            (self.isIncoming ? [self.expirationTimerView autoPinLeadingToSuperviewMargin]
                             : [self.expirationTimerView autoPinTrailingToSuperviewMargin]),
            [self.footerView autoSetDimension:ALDimensionHeight toSize:self.footerHeight],
        ]];
    } else if (attributedText) {
        [self.viewConstraints addObjectsFromArray:@[
            [self.footerLabel autoVCenterInSuperview],
            (self.isIncoming ? [self.footerLabel autoPinLeadingToSuperviewMargin]
                             : [self.footerLabel autoPinTrailingToSuperviewMargin]),
            [self.footerView autoSetDimension:ALDimensionHeight toSize:self.footerHeight],
            [self.footerLabel autoSetDimension:ALDimensionWidth
                                        toSize:maxFooterLabelWidth
                                      relation:NSLayoutRelationLessThanOrEqual],
        ]];
    } else {
        OWSFail(@"%@ Cell unexpectedly has neither expiration timer nor footer text.", self.logTag);
    }
}

- (UIFont *)dateHeaderDateFont
{
    return UIFont.ows_dynamicTypeCaption1Font.ows_mediumWeight;
}

- (UIFont *)dateHeaderTimeFont
{
    return UIFont.ows_dynamicTypeCaption1Font;
}

#pragma mark - Avatar

// Returns YES IFF the avatar view is appropriate and configured.
- (BOOL)updateAvatarView
{
    if (!self.viewItem.isGroupThread) {
        return NO;
    }
    if (self.viewItem.interaction.interactionType != OWSInteractionType_IncomingMessage) {
        return NO;
    }
    if (self.viewItem.shouldHideAvatar) {
        return NO;
    }

    OWSContactsManager *contactsManager = self.delegate.contactsManager;
    if (contactsManager == nil) {
        OWSFail(@"%@ contactsManager should not be nil", self.logTag);
        return NO;
    }

    TSIncomingMessage *incomingMessage = (TSIncomingMessage *)self.viewItem.interaction;
    OWSAvatarBuilder *avatarBuilder = [[OWSContactAvatarBuilder alloc] initWithSignalId:incomingMessage.authorId
                                                                               diameter:self.avatarSize
                                                                        contactsManager:contactsManager];
    self.avatarView.image = [avatarBuilder build];
    self.avatarView.hidden = NO;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationName_OtherUsersProfileDidChange
                                               object:nil];

    return YES;
}

- (NSUInteger)avatarSize
{
    return 24.f;
}

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    if (!self.viewItem.isGroupThread) {
        return;
    }
    if (self.viewItem.interaction.interactionType != OWSInteractionType_IncomingMessage) {
        return;
    }
    if (self.viewItem.shouldHideAvatar) {
        return;
    }

    NSString *recipientId = notification.userInfo[kNSNotificationKey_ProfileRecipientId];
    if (recipientId.length == 0) {
        return;
    }
    TSIncomingMessage *incomingMessage = (TSIncomingMessage *)self.viewItem.interaction;

    if (![incomingMessage.authorId isEqualToString:recipientId]) {
        return;
    }

    [self updateAvatarView];
}

#pragma mark - Measurement

- (CGSize)cellSizeWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(self.layoutInfo);
    OWSAssert(self.layoutInfo.viewWidth > 0);
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);
    OWSAssert(self.messageBubbleView);

    self.messageBubbleView.viewItem = self.viewItem;
    self.messageBubbleView.cellMediaCache = self.delegate.cellMediaCache;
    CGSize messageBubbleSize = [self.messageBubbleView measureSize];

    CGSize cellSize = messageBubbleSize;

    OWSAssert(cellSize.width > 0 && cellSize.height > 0);

    cellSize.height += self.dateHeaderHeight;
    if (self.shouldShowFooter) {
        cellSize.height += self.footerVSpacing;
        cellSize.height += self.footerHeight;
    }

    cellSize = CGSizeCeil(cellSize);

    return cellSize;
}

- (CGFloat)dateHeaderHeight
{
    if (self.viewItem.shouldShowDate) {
        // Add 5pt spacing above and below the date header.
        return (CGFloat)ceil(MAX(self.dateHeaderDateFont.lineHeight, self.dateHeaderTimeFont.lineHeight) + 10.f);
    } else {
        return 0.f;
    }
}

#pragma mark - Reuse

- (void)prepareForReuse
{
    [super prepareForReuse];

    [NSLayoutConstraint deactivateConstraints:self.viewConstraints];
    self.viewConstraints = [NSMutableArray new];

    [self.messageBubbleView prepareForReuse];
    [self.messageBubbleView unloadContent];

    self.dateHeaderLabel.text = nil;
    self.dateHeaderLabel.hidden = YES;
    self.footerLabel.text = nil;
    self.footerLabel.hidden = YES;
    self.avatarView.image = nil;
    self.avatarView.hidden = YES;

    [self.expirationTimerView clearAnimations];
    [self.expirationTimerView removeFromSuperview];
    self.expirationTimerView = nil;

    [self hideMenuControllerIfNecessary];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notifications

- (void)setIsCellVisible:(BOOL)isCellVisible {
    BOOL didChange = self.isCellVisible != isCellVisible;

    [super setIsCellVisible:isCellVisible];

    if (!didChange) {
        return;
    }

    [self ensureMediaLoadState];

    if (isCellVisible) {
        if (self.message.shouldStartExpireTimer) {
            [self.expirationTimerView ensureAnimations];
        } else {
            [self.expirationTimerView clearAnimations];
        }
    } else {
        [self.expirationTimerView clearAnimations];

        [self hideMenuControllerIfNecessary];
    }
}

#pragma mark - Gesture recognizers

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    if (sender.state != UIGestureRecognizerStateRecognized) {
        DDLogVerbose(@"%@ Ignoring tap on message: %@", self.logTag, self.viewItem.interaction.debugDescription);
        return;
    }

    if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        if (outgoingMessage.messageState == TSOutgoingMessageStateFailed) {
            [self.delegate didTapFailedOutgoingMessage:outgoingMessage];
            return;
        } else if (outgoingMessage.messageState == TSOutgoingMessageStateSending) {
            // Ignore taps on outgoing messages being sent.
            return;
        }
    }

    [self.messageBubbleView handleTapGesture:sender];
}

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)sender
{
    OWSAssert(self.delegate);

    if (sender.state != UIGestureRecognizerStateBegan) {
        return;
    }

    if (self.viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.viewItem.interaction;
        if (outgoingMessage.messageState == TSOutgoingMessageStateFailed) {
            // Ignore long press on unsent messages.
            return;
        } else if (outgoingMessage.messageState == TSOutgoingMessageStateSending) {
            // Ignore long press on outgoing messages being sent.
            return;
        }
    }

    CGPoint locationInMessageBubble = [sender locationInView:self.messageBubbleView];
    switch ([self.messageBubbleView gestureLocationForLocation:locationInMessageBubble]) {
        case OWSMessageGestureLocation_Default:
        case OWSMessageGestureLocation_OversizeText: {
            CGPoint location = [sender locationInView:self];
            [self showTextMenuController:location];
            break;
        }
        case OWSMessageGestureLocation_Media: {
            CGPoint location = [sender locationInView:self];
            [self showMediaMenuController:location];
            break;
        }
        case OWSMessageGestureLocation_QuotedReply: {
            CGPoint location = [sender locationInView:self];
            [self showDefaultMenuController:location];
            break;
        }
    }
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)panRecognizer
{
    OWSAssert(self.delegate);

    [self.delegate didPanWithGestureRecognizer:panRecognizer viewItem:self.viewItem];
}

#pragma mark - UIMenuController

- (void)showTextMenuController:(CGPoint)fromLocation
{
    [self showMenuController:fromLocation menuItems:self.viewItem.textMenuControllerItems];
}

- (void)showMediaMenuController:(CGPoint)fromLocation
{
    [self showMenuController:fromLocation menuItems:self.viewItem.mediaMenuControllerItems];
}

- (void)showDefaultMenuController:(CGPoint)fromLocation
{
    [self showMenuController:fromLocation menuItems:self.viewItem.defaultMenuControllerItems];
}

- (void)showMenuController:(CGPoint)fromLocation menuItems:(NSArray *)menuItems
{
    if (menuItems.count < 1) {
        OWSFail(@"%@ No menu items to present.", self.logTag);
        return;
    }

    // We don't want taps on messages to hide the keyboard,
    // so we only let messages become first responder
    // while they are trying to present the menu controller.
    self.isPresentingMenuController = YES;

    [self becomeFirstResponder];

    if ([UIMenuController sharedMenuController].isMenuVisible) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    }

    // We use custom action selectors so that we can control
    // the ordering of the actions in the menu.
    [UIMenuController sharedMenuController].menuItems = menuItems;
    CGRect targetRect = CGRectMake(fromLocation.x, fromLocation.y, 1, 1);
    [[UIMenuController sharedMenuController] setTargetRect:targetRect inView:self];
    [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];
}

- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender
{
    return [self.viewItem canPerformAction:action];
}

- (void)copyTextAction:(nullable id)sender
{
    [self.viewItem copyTextAction];
}

- (void)copyMediaAction:(nullable id)sender
{
    [self.viewItem copyMediaAction];
}

- (void)shareTextAction:(nullable id)sender
{
    [self.viewItem shareTextAction];
}

- (void)shareMediaAction:(nullable id)sender
{
    [self.viewItem shareMediaAction];
}

- (void)saveMediaAction:(nullable id)sender
{
    [self.viewItem saveMediaAction];
}

- (void)deleteAction:(nullable id)sender
{
    [self.viewItem deleteAction];
}

- (void)metadataAction:(nullable id)sender
{
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    [self.delegate showMetadataViewForViewItem:self.viewItem];
}

- (void)replyAction:(nullable id)sender
{
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);

    [self.delegate conversationCell:self didTapReplyForViewItem:self.viewItem];
}

- (BOOL)canBecomeFirstResponder
{
    return self.isPresentingMenuController;
}

- (void)didHideMenuController:(NSNotification *)notification
{
    self.isPresentingMenuController = NO;
}

- (void)setIsPresentingMenuController:(BOOL)isPresentingMenuController
{
    if (_isPresentingMenuController == isPresentingMenuController) {
        return;
    }

    _isPresentingMenuController = isPresentingMenuController;

    if (isPresentingMenuController) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didHideMenuController:)
                                                     name:UIMenuControllerDidHideMenuNotification
                                                   object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:UIMenuControllerDidHideMenuNotification
                                                      object:nil];
    }
}

- (void)hideMenuControllerIfNecessary
{
    if (self.isPresentingMenuController) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    }
    self.isPresentingMenuController = NO;
}

@end

NS_ASSUME_NONNULL_END
