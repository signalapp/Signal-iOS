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
@property (nonatomic) NSArray<NSLayoutConstraint *> *layoutConstraints;
@property (nonatomic) UIStackView *stackView;

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

    self.titleLabel = [UILabel new];
    self.titleLabel.textColor = [UIColor blackColor];
    self.titleLabel.text = NSLocalizedString(@"CONVERSATION_VIEW_CONTACTS_OFFER_TITLE",
        @"Title for the group of buttons show for unknown contacts offering to add them to contacts, etc.");
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;

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

    self.stackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.titleLabel,
    ]];
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = self.vSpacing;
    self.stackView.alignment = UIStackViewAlignmentCenter;
    self.stackView.layoutMargins = UIEdgeInsetsZero;
    [self.contentView addSubview:self.stackView];
}

- (void)configureFonts
{
    self.titleLabel.font = UIFont.ows_dynamicTypeBodyFont.ows_mediumWeight;

    UIFont *buttonFont = UIFont.ows_dynamicTypeBodyFont;
    self.addToContactsButton.titleLabel.font = buttonFont;
    self.addToProfileWhitelistButton.titleLabel.font = buttonFont;
    self.blockButton.titleLabel.font = buttonFont;
}

- (UIButton *)createButtonWithTitle:(NSString *)title selector:(SEL)selector
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor ows_materialBlueColor] forState:UIControlStateNormal];
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    [button setBackgroundColor:[UIColor colorWithRGBHex:0xf5f5f5]];
    button.layer.cornerRadius = 5.f;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)loadForDisplayWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(self.layoutInfo);
    OWSAssert(self.layoutInfo.viewWidth > 0);
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[OWSContactOffersInteraction class]]);

    [self configureFonts];

    OWSContactOffersInteraction *interaction = (OWSContactOffersInteraction *)self.viewItem.interaction;

    OWSAssert(
        interaction.hasBlockOffer || interaction.hasAddToContactsOffer || interaction.hasAddToProfileWhitelistOffer);

    CGFloat buttonWidth = 0.f;
    if (interaction.hasAddToContactsOffer) {
        [self.stackView addArrangedSubview:self.addToContactsButton];
        buttonWidth = MAX(buttonWidth, [self.addToContactsButton sizeThatFits:CGSizeZero].width);
    }
    if (interaction.hasAddToProfileWhitelistOffer) {
        [self.stackView addArrangedSubview:self.addToProfileWhitelistButton];
        buttonWidth = MAX(buttonWidth, [self.addToProfileWhitelistButton sizeThatFits:CGSizeZero].width);
    }
    if (interaction.hasBlockOffer) {
        [self.stackView addArrangedSubview:self.blockButton];
        buttonWidth = MAX(buttonWidth, [self.blockButton sizeThatFits:CGSizeZero].width);
    }

    buttonWidth = (2 * self.buttonHPadding + (CGFloat)ceil(buttonWidth));

    CGFloat hMargins = (self.layoutInfo.fullWidthGutterLeading + self.layoutInfo.fullWidthGutterTrailing);
    CGFloat maxButtonWidth = self.layoutInfo.viewWidth - hMargins;
    buttonWidth = MIN(buttonWidth, maxButtonWidth);

    CGFloat buttonHeight = self.buttonHeight;
    [NSLayoutConstraint deactivateConstraints:self.layoutConstraints];
    self.layoutConstraints = @[
        [self.addToContactsButton autoSetDimension:ALDimensionWidth toSize:buttonWidth],
        [self.addToProfileWhitelistButton autoSetDimension:ALDimensionWidth toSize:buttonWidth],
        [self.blockButton autoSetDimension:ALDimensionWidth toSize:buttonWidth],

        [self.addToContactsButton autoSetDimension:ALDimensionHeight toSize:buttonHeight],
        [self.addToProfileWhitelistButton autoSetDimension:ALDimensionHeight toSize:buttonHeight],
        [self.blockButton autoSetDimension:ALDimensionHeight toSize:buttonHeight],

        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.topVMargin],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:self.bottomVMargin],
        // TODO: Honor "full-width gutters"?
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeLeading withInset:self.layoutInfo.fullWidthGutterLeading],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeTrailing withInset:self.layoutInfo.fullWidthGutterTrailing],
    ];
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

- (CGFloat)buttonHPadding
{
    return 60.f;
}

- (CGFloat)vSpacing
{
    return 5.f;
}

- (CGFloat)buttonHeight
{
    return (self.buttonVPadding + CGSizeCeil([self.addToContactsButton sizeThatFits:CGSizeZero]).height);
}

- (CGSize)cellSize
{
    OWSAssert(self.layoutInfo);
    OWSAssert(self.layoutInfo.viewWidth > 0);
    OWSAssert(self.viewItem);
    OWSAssert([self.viewItem.interaction isKindOfClass:[OWSContactOffersInteraction class]]);

    [self configureFonts];

    OWSContactOffersInteraction *interaction = (OWSContactOffersInteraction *)self.viewItem.interaction;

    CGSize result = CGSizeMake(self.layoutInfo.viewWidth, 0);
    result.height += self.topVMargin;
    result.height += self.bottomVMargin;

    result.height += ceil([self.titleLabel sizeThatFits:CGSizeZero].height);

    int buttonCount = ((interaction.hasBlockOffer ? 1 : 0) + (interaction.hasAddToContactsOffer ? 1 : 0)
        + (interaction.hasAddToProfileWhitelistOffer ? 1 : 0));
    result.height += buttonCount * (self.vSpacing + self.buttonHeight);

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

- (void)prepareForReuse
{
    [super prepareForReuse];

    [self.addToContactsButton removeFromSuperview];
    [self.addToProfileWhitelistButton removeFromSuperview];
    [self.blockButton removeFromSuperview];
}

@end

NS_ASSUME_NONNULL_END
