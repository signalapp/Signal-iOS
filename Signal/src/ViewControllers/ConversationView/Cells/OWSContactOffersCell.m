//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSContactOffersCell.h"
#import "ConversationViewItem.h"
#import "Signal-Swift.h"
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalServiceKit/OWSContactOffersInteraction.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactOffersCell ()

@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UIButton *addToContactsButton;
@property (nonatomic) UIButton *addToProfileWhitelistButton;
@property (nonatomic) UIButton *blockButton;
@property (nonatomic) NSArray<NSLayoutConstraint *> *layoutConstraints;
@property (nonatomic) UIStackView *stackView;
@property (nonatomic) UIStackView *buttonStackView;

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
    OWSAssertDebug(!self.titleLabel);

    self.layoutMargins = UIEdgeInsetsZero;
    self.contentView.layoutMargins = UIEdgeInsetsZero;
    self.layoutConstraints = @[];

    self.titleLabel = [UILabel new];
    self.titleLabel.text = NSLocalizedString(@"CONVERSATION_VIEW_CONTACTS_OFFER_TITLE",
        @"Title for the group of buttons show for unknown contacts offering to add them to contacts, etc.");
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;

    self.addToContactsButton = [self
        createButtonWithTitle:
            NSLocalizedString(@"CONVERSATION_VIEW_ADD_TO_CONTACTS_OFFER",
                @"Message shown in conversation view that offers to add an unknown user to your phone's contacts.")
                     selector:@selector(addToContacts)];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _addToContactsButton);
    self.addToProfileWhitelistButton = [self
        createButtonWithTitle:NSLocalizedString(@"CONVERSATION_VIEW_ADD_USER_TO_PROFILE_WHITELIST_OFFER",
                                  @"Message shown in conversation view that offers to share your profile with a user.")
                     selector:@selector(addToProfileWhitelist)];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _addToProfileWhitelistButton);
    self.blockButton =
        [self createButtonWithTitle:NSLocalizedString(@"CONVERSATION_VIEW_UNKNOWN_CONTACT_BLOCK_OFFER",
                                        @"Message shown in conversation view that offers to block an unknown user.")
                           selector:@selector(block)];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _blockButton);

    UIStackView *buttonStackView = [[UIStackView alloc] initWithArrangedSubviews:self.buttons];
    buttonStackView.axis = UILayoutConstraintAxisVertical;
    buttonStackView.spacing = self.vSpacing;
    self.buttonStackView = buttonStackView;

    self.stackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.titleLabel,
        buttonStackView,
    ]];
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = self.vSpacing;
    self.stackView.alignment = UIStackViewAlignmentCenter;
    [self.contentView addSubview:self.stackView];
}

- (void)configureFonts
{
    self.titleLabel.font = UIFont.ows_dynamicTypeSubheadlineFont;

    UIFont *buttonFont = UIFont.ows_dynamicTypeSubheadlineFont.ows_mediumWeight;
    self.addToContactsButton.titleLabel.font = buttonFont;
    self.addToProfileWhitelistButton.titleLabel.font = buttonFont;
    self.blockButton.titleLabel.font = buttonFont;
}

- (UIButton *)createButtonWithTitle:(NSString *)title selector:(SEL)selector
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    button.layer.cornerRadius = 4.f;
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 10.f, 0, 10.f);
    return button;
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)loadForDisplay
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.conversationStyle.viewWidth > 0);
    OWSAssertDebug(self.viewItem);
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[OWSContactOffersInteraction class]]);

    self.backgroundColor = [Theme backgroundColor];

    [self configureFonts];

    self.titleLabel.textColor = Theme.secondaryColor;
    for (UIButton *button in self.buttons) {
        [button setTitleColor:[UIColor ows_signalBlueColor] forState:UIControlStateNormal];
        [button setBackgroundColor:Theme.conversationButtonBackgroundColor];
    }

    OWSContactOffersInteraction *interaction = (OWSContactOffersInteraction *)self.viewItem.interaction;

    OWSAssertDebug(
        interaction.hasBlockOffer || interaction.hasAddToContactsOffer || interaction.hasAddToProfileWhitelistOffer);

    self.addToContactsButton.hidden = !interaction.hasAddToContactsOffer;
    self.addToProfileWhitelistButton.hidden = !interaction.hasAddToProfileWhitelistOffer;
    self.blockButton.hidden = !interaction.hasBlockOffer;

    [NSLayoutConstraint deactivateConstraints:self.layoutConstraints];
    self.layoutConstraints = @[
        [self.addToContactsButton autoSetDimension:ALDimensionHeight toSize:self.buttonHeight],
        [self.addToProfileWhitelistButton autoSetDimension:ALDimensionHeight toSize:self.buttonHeight],
        [self.blockButton autoSetDimension:ALDimensionHeight toSize:self.buttonHeight],

        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:self.topVMargin],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:self.bottomVMargin],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeLeading
                                         withInset:self.conversationStyle.fullWidthGutterLeading],
        [self.stackView autoPinEdgeToSuperviewEdge:ALEdgeTrailing
                                         withInset:self.conversationStyle.fullWidthGutterTrailing],
    ];

    // This hack fixes a bug that I don't understand.
    //
    // On an iPhone 5C running iOS 10.3.3,
    //
    // * Alice is a contact for which we should show some but not all contact offer buttons.
    // * Delete thread with Alice.
    // * Send yourself a message from Alice.
    // * Open conversation with Alice.
    //
    // Expected: Some (but not all) offer buttons are displayed.
    // Observed: All offer buttons are displayed, in a cramped layout.
    for (UIButton *button in self.buttons) {
        [button removeFromSuperview];
    }
    for (UIButton *button in self.buttons) {
        if (!button.hidden) {
            [self.buttonStackView addArrangedSubview:button];
        }
    }
}

- (NSArray<UIButton *> *)buttons
{
    return @[
        self.addToContactsButton,
        self.addToProfileWhitelistButton,
        self.blockButton,
    ];
}

- (CGFloat)topVMargin
{
    return 0.f;
}

- (CGFloat)bottomVMargin
{
    return 0.f;
}

- (CGFloat)vSpacing
{
    return 8.f;
}

- (CGFloat)buttonHeight
{
    return (24.f + self.addToContactsButton.titleLabel.font.lineHeight);
}

- (CGSize)cellSize
{
    OWSAssertDebug(self.conversationStyle);
    OWSAssertDebug(self.conversationStyle.viewWidth > 0);
    OWSAssertDebug(self.viewItem);
    OWSAssertDebug([self.viewItem.interaction isKindOfClass:[OWSContactOffersInteraction class]]);

    [self configureFonts];

    OWSContactOffersInteraction *interaction = (OWSContactOffersInteraction *)self.viewItem.interaction;

    CGSize result = CGSizeMake(self.conversationStyle.viewWidth, 0);
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
    OWSAssertDebug(self.viewItem);
    OWSAssertDebug(self.viewItem.interaction);
    if (![self.viewItem.interaction isKindOfClass:[OWSContactOffersInteraction class]]) {
        OWSFailDebug(@"expected OWSContactOffersInteraction but found: %@", self.viewItem.interaction);
        return nil;
    }
    return (OWSContactOffersInteraction *)self.viewItem.interaction;
}

- (void)addToContacts
{
    OWSAssertDebug(self.delegate);
    OWSAssertDebug(self.interaction);

    [self.delegate tappedAddToContactsOfferMessage:self.interaction];
}

- (void)addToProfileWhitelist
{
    OWSAssertDebug(self.delegate);
    OWSAssertDebug(self.interaction);

    [self.delegate tappedAddToProfileWhitelistOfferMessage:self.interaction];
}

- (void)block
{
    OWSAssertDebug(self.delegate);
    OWSAssertDebug(self.interaction);

    [self.delegate tappedUnknownContactBlockOfferMessage:self.interaction];
}

@end

NS_ASSUME_NONNULL_END
