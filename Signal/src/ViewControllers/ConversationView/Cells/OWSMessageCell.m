//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageCell.h"
#import "OWSContactAvatarBuilder.h"
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
@property (nonatomic) UIView *dateHeaderView;
@property (nonatomic) UIView *dateStrokeView;
@property (nonatomic) UILabel *dateHeaderLabel;
@property (nonatomic) AvatarImageView *avatarView;

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

    self.dateHeaderView = [UIView new];

    self.dateStrokeView = [UIView new];
    self.dateStrokeView.backgroundColor = [UIColor lightGrayColor];
    [self.dateHeaderView addSubview:self.dateStrokeView];

    self.dateHeaderLabel = [UILabel new];
    self.dateHeaderLabel.font = self.dateHeaderDateFont;
    self.dateHeaderLabel.textAlignment = NSTextAlignmentCenter;
    self.dateHeaderLabel.textColor = [UIColor lightGrayColor];
    [self.dateHeaderView addSubview:self.dateHeaderLabel];

    [self.dateStrokeView autoPinWidthToSuperview];
    [self.dateStrokeView autoSetDimension:ALDimensionHeight toSize:1.f];
    [self.dateHeaderLabel autoPinWidthToSuperview];
    [self.dateHeaderLabel autoVCenterInSuperview];
    // TODO: offset.
    [self.dateStrokeView autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:self.dateHeaderLabel withOffset:0.f];

    self.avatarView = [[AvatarImageView alloc] init];
    [self.contentView addSubview:self.avatarView];
    [self.avatarView autoSetDimension:ALDimensionWidth toSize:self.avatarSize];
    [self.avatarView autoSetDimension:ALDimensionHeight toSize:self.avatarSize];

    // Hide these views by default.
    self.avatarView.hidden = YES;

    [self.messageBubbleView autoPinBottomToSuperviewMarginWithInset:0];

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

- (void)setConversationStyle:(nullable ConversationStyle *)conversationStyle
{
    [super setConversationStyle:conversationStyle];

    self.messageBubbleView.conversationStyle = conversationStyle;
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
    OWSAssert(self.conversationStyle);
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

    if (self.isIncoming) {
        [self.viewConstraints addObjectsFromArray:@[
            [self.messageBubbleView autoPinEdgeToSuperviewEdge:ALEdgeLeading
                                                     withInset:self.conversationStyle.gutterLeading],
            [self.messageBubbleView autoPinEdgeToSuperviewEdge:ALEdgeTrailing
                                                     withInset:self.conversationStyle.gutterTrailing
                                                      relation:NSLayoutRelationGreaterThanOrEqual],
        ]];
    } else {
        [self.viewConstraints addObjectsFromArray:@[
            [self.messageBubbleView autoPinEdgeToSuperviewEdge:ALEdgeLeading
                                                     withInset:self.conversationStyle.gutterLeading
                                                      relation:NSLayoutRelationGreaterThanOrEqual],
            [self.messageBubbleView autoPinEdgeToSuperviewEdge:ALEdgeTrailing
                                                     withInset:self.conversationStyle.gutterTrailing],
        ]];
    }

    [self updateDateHeader];

    if ([self updateAvatarView]) {
        CGFloat avatarBottomMargin = round(self.conversationStyle.lastTextLineAxis - self.avatarSize * 0.5f);
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
    OWSAssert(self.conversationStyle);

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

        [self.contentView addSubview:self.dateHeaderView];
        [self.viewConstraints addObjectsFromArray:@[
            [self.dateHeaderView autoPinLeadingToSuperviewMarginWithInset:self.conversationStyle.gutterLeading],
            [self.dateHeaderView autoPinTrailingToSuperviewMarginWithInset:self.conversationStyle.gutterTrailing],
            [self.dateHeaderView autoPinEdgeToSuperviewEdge:ALEdgeTop],
            [self.dateHeaderView autoSetDimension:ALDimensionHeight toSize:self.dateHeaderHeight],

            [self.messageBubbleView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.dateHeaderView],
        ]];
    } else {
        [self.viewConstraints addObjectsFromArray:@[
            [self.messageBubbleView autoPinEdgeToSuperviewEdge:ALEdgeTop],
        ]];
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
    OWSAssert(self.conversationStyle);
    OWSAssert(self.conversationStyle.viewWidth > 0);
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[TSMessage class]]);
    OWSAssert(self.messageBubbleView);

    self.messageBubbleView.viewItem = self.viewItem;
    self.messageBubbleView.cellMediaCache = self.delegate.cellMediaCache;
    CGSize messageBubbleSize = [self.messageBubbleView measureSize];

    CGSize cellSize = messageBubbleSize;

    OWSAssert(cellSize.width > 0 && cellSize.height > 0);

    cellSize.height += self.dateHeaderHeight;

    cellSize = CGSizeCeil(cellSize);

    return cellSize;
}

- (CGFloat)dateHeaderVSpacing
{
    return 24.f;
}

- (CGFloat)dateHeaderHeight
{
    if (self.viewItem.shouldShowDate) {
        // Add 5pt spacing above and below the date header.
        CGFloat textHeight = MAX(self.dateHeaderDateFont.capHeight, self.dateHeaderTimeFont.capHeight);
        return (CGFloat)ceil(textHeight + self.dateHeaderVSpacing * 2);
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

    [self.dateHeaderView removeFromSuperview];

    self.avatarView.image = nil;
    self.avatarView.hidden = YES;

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

    if (!isCellVisible) {
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
