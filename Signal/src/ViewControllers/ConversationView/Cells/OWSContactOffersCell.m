//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactOffersCell.h"
#import "ConversationViewItem.h"
#import "Signal-Swift.h"
#import <SignalMessaging/OWSContactOffersInteraction.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactOffersCell ()

@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UIButton *addToContactsButton;
@property (nonatomic) UIButton *addToProfileWhitelistButton;
@property (nonatomic) UIButton *blockButton;

@end

#pragma mark -

@implementation OWSContactOffersCell

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
    OWSAssert(!self.titleLabel);

    self.preservesSuperviewLayoutMargins = NO;
    self.contentView.preservesSuperviewLayoutMargins = NO;
    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;

    //    [self setTranslatesAutoresizingMaskIntoConstraints:NO];

    self.titleLabel = [UILabel new];
    self.titleLabel.textColor = [UIColor blackColor];
    self.titleLabel.font = [self titleFont];
    self.titleLabel.text = NSLocalizedString(@"CONVERSATION_VIEW_CONTACTS_OFFER_TITLE",
        @"Title for the group of buttons show for unknown contacts offering to add them to contacts, etc.");
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.titleLabel];

    self.addToContactsButton = [self
        createButtonWithTitle:
            NSLocalizedString(@"CONVERSATION_VIEW_ADD_TO_CONTACTS_OFFER",
                @"Message shown in conversation view that offers to add an unknown user to your phone's contacts.")
                     selector:@selector(addToContacts)];
    self.addToProfileWhitelistButton = [self
        createButtonWithTitle:NSLocalizedString(@"CONVERSATION_VIEW_ADD_USER_TO_PROFILE_WHITELIST_OFFER",
                                  @"Message shown in conversation view that offers to share your profile with a user.")
                     selector:@selector(addToProfileWhitelist)];
    self.blockButton =
        [self createButtonWithTitle:NSLocalizedString(@"CONVERSATION_VIEW_UNKNOWN_CONTACT_BLOCK_OFFER",
                                        @"Message shown in conversation view that offers to block an unknown user.")
                           selector:@selector(block)];
}

- (UIButton *)createButtonWithTitle:(NSString *)title selector:(SEL)selector
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor ows_materialBlueColor] forState:UIControlStateNormal];
    button.titleLabel.font = self.buttonFont;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    [button setBackgroundColor:[UIColor colorWithRGBHex:0xf5f5f5]];
    button.layer.cornerRadius = 5.f;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:button];
    return button;
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)loadForDisplayWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[OWSContactOffersInteraction class]]);

    OWSContactOffersInteraction *interaction = (OWSContactOffersInteraction *)self.viewItem.interaction;

    OWSAssert(
        interaction.hasBlockOffer || interaction.hasAddToContactsOffer || interaction.hasAddToProfileWhitelistOffer);

    [self setNeedsLayout];
}

- (UIFont *)titleFont
{
    return UIFont.ows_dynamicTypeBodyFont.ows_mediumWeight;
}

- (UIFont *)buttonFont
{
    return UIFont.ows_dynamicTypeBodyFont;
}

- (CGFloat)hMargin
{
    return 10.f;
}

- (CGFloat)topVMargin
{
    return 5.f;
}

- (CGFloat)bottomVMargin
{
    return 5.f;
}

- (CGFloat)buttonVPadding
{
    return 5.f;
}

- (CGFloat)buttonVSpacing
{
    return 5.f;
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    OWSContactOffersInteraction *interaction = (OWSContactOffersInteraction *)self.viewItem.interaction;

    // We're using a bit of a hack to get this and the unread indicator to layout as
    // "full width" cells.  These cells will end up with an erroneous left margin that we
    // want to reverse.
    CGFloat contentWidth = self.width;
    CGFloat left = -self.left;

    CGRect titleFrame = self.contentView.bounds;
    titleFrame.origin = CGPointMake(left + self.hMargin, self.topVMargin);
    titleFrame.size.width = contentWidth - 2 * self.hMargin;
    titleFrame.size.height = ceil([self.titleLabel sizeThatFits:CGSizeZero].height);
    self.titleLabel.frame = titleFrame;

    __block CGFloat y = round(self.titleLabel.bottom + self.buttonVSpacing);
    void (^layoutButton)(UIButton *, BOOL) = ^(UIButton *button, BOOL isVisible) {
        if (isVisible) {
            button.hidden = NO;

            button.frame = CGRectMake(round(left + self.hMargin),
                round(y),
                floor(contentWidth - 2 * self.hMargin),
                ceil([button sizeThatFits:CGSizeZero].height + self.buttonVPadding));
            y = round(button.bottom + self.buttonVSpacing);
        } else {
            button.hidden = YES;
        }
    };

    layoutButton(self.addToContactsButton, interaction.hasAddToContactsOffer);
    layoutButton(self.addToProfileWhitelistButton, interaction.hasAddToProfileWhitelistOffer);
    layoutButton(self.blockButton, interaction.hasBlockOffer);
}

- (CGSize)cellSize
{
    OWSAssert(self.layoutInfo);
    OWSAssert(self.layoutInfo.viewWidth > 0);
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[OWSContactOffersInteraction class]]);

    OWSContactOffersInteraction *interaction = (OWSContactOffersInteraction *)self.viewItem.interaction;

    // TODO: Should we use viewWidth?
    CGSize result = CGSizeMake(self.layoutInfo.viewWidth, 0);
    result.height += self.topVMargin;
    result.height += self.bottomVMargin;

    result.height += ceil([self.titleLabel sizeThatFits:CGSizeZero].height);

    int buttonCount = ((interaction.hasBlockOffer ? 1 : 0) + (interaction.hasAddToContactsOffer ? 1 : 0)
        + (interaction.hasAddToProfileWhitelistOffer ? 1 : 0));
    result.height += buttonCount
        * (self.buttonVPadding + self.buttonVSpacing + ceil([self.addToContactsButton sizeThatFits:CGSizeZero].height));

    return result;
}

#pragma mark - Events

- (nullable OWSContactOffersInteraction *)interaction
{
    OWSAssert(self.viewItem);
    OWSAssert(self.viewItem.interaction);
    if (![self.viewItem.interaction isKindOfClass:[OWSContactOffersInteraction class]]) {
        OWSFail(@"%@ expected OWSContactOffersInteraction but found: %@", self.logTag, self.viewItem.interaction);
        return nil;
    }
    return (OWSContactOffersInteraction *)self.viewItem.interaction;
}

- (void)addToContacts
{
    OWSAssert(self.delegate);
    OWSAssert(self.interaction);

    [self.delegate tappedAddToContactsOfferMessage:self.interaction];
}

- (void)addToProfileWhitelist
{
    OWSAssert(self.delegate);
    OWSAssert(self.interaction);

    [self.delegate tappedAddToProfileWhitelistOfferMessage:self.interaction];
}

- (void)block
{
    OWSAssert(self.delegate);
    OWSAssert(self.interaction);

    [self.delegate tappedUnknownContactBlockOfferMessage:self.interaction];
}

@end

NS_ASSUME_NONNULL_END
