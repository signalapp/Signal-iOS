//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSContactOffersCell.h"
#import "NSBundle+JSQMessages.h"
#import "OWSContactOffersInteraction.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <JSQMessagesViewController/UIView+JSQMessages.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSContactOffersCell ()

@property (nonatomic, nullable) OWSContactOffersInteraction *interaction;

@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UIButton *addToContactsButton;
@property (nonatomic) UIButton *addToProfileWhitelistButton;
@property (nonatomic) UIButton *blockButton;
//@property (nonatomic) UIView *bannerView;
//@property (nonatomic) UIView *bannerTopHighlightView;
//@property (nonatomic) UIView *bannerBottomHighlightView1;
//@property (nonatomic) UIView *bannerBottomHighlightView2;
//@property (nonatomic) UILabel *titleLabel;
//@property (nonatomic) UILabel *subtitleLabel;

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

    [self setTranslatesAutoresizingMaskIntoConstraints:NO];

    //    self.backgroundColor = [UIColor whiteColor];

    self.titleLabel = [UILabel new];
    self.titleLabel.textColor = [UIColor blackColor];
    self.titleLabel.font = [self titleFont];
    self.titleLabel.text = NSLocalizedString(@"CONVERSATION_VIEW_CONTACTS_OFFER_TITLE",
        @"Title for the group of buttons show for unknown contacts offering to add them to contacts, etc.");
    // The subtitle may wrap to a second line.
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.titleLabel];

    self.addToContactsButton = [self
        createButtonWithTitle:
            NSLocalizedString(@"CONVERSATION_VIEW_ADD_TO_CONTACTS_OFFER",
                @"Message shown in conversation view that offers to add an unknown user to your phone's contacts.")];
    self.addToProfileWhitelistButton =
        [self createButtonWithTitle:
                  NSLocalizedString(@"CONVERSATION_VIEW_ADD_USER_TO_PROFILE_WHITELIST_OFFER",
                      @"Message shown in conversation view that offers to share your profile with a user.")];
    self.blockButton =
        [self createButtonWithTitle:NSLocalizedString(@"CONVERSATION_VIEW_UNKNOWN_CONTACT_BLOCK_OFFER",
                                        @"Message shown in conversation view that offers to block an unknown user.")];

    //    self.bannerView = [UIView new];
    //    self.bannerView.backgroundColor = [UIColor colorWithRGBHex:0xf6eee3];
    //    [self.contentView addSubview:self.bannerView];
    //
    //    self.bannerTopHighlightView = [UIView new];
    //    self.bannerTopHighlightView.backgroundColor = [UIColor colorWithRGBHex:0xf9f3eb];
    //    [self.bannerView addSubview:self.bannerTopHighlightView];
    //
    //    self.bannerBottomHighlightView1 = [UIView new];
    //    self.bannerBottomHighlightView1.backgroundColor = [UIColor colorWithRGBHex:0xd1c6b8];
    //    [self.bannerView addSubview:self.bannerBottomHighlightView1];
    //
    //    self.bannerBottomHighlightView2 = [UIView new];
    //    self.bannerBottomHighlightView2.backgroundColor = [UIColor colorWithRGBHex:0xdbcfc0];
    //    [self.bannerView addSubview:self.bannerBottomHighlightView2];
    //
    //    self.titleLabel = [UILabel new];
    //    self.titleLabel.textColor = [UIColor colorWithRGBHex:0x403e3b];
    //    self.titleLabel.font = [self titleFont];
    //    [self.bannerView addSubview:self.titleLabel];
    //
    //    self.subtitleLabel = [UILabel new];
    //    self.subtitleLabel.textColor = [UIColor ows_infoMessageBorderColor];
    //    self.subtitleLabel.font = [self subtitleFont];
    //    // The subtitle may wrap to a second line.
    //    self.subtitleLabel.numberOfLines = 0;
    //    self.subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    //    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    //    [self.contentView addSubview:self.subtitleLabel];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    [self addGestureRecognizer:tap];
}

- (UIButton *)createButtonWithTitle:(NSString *)title
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor ows_materialBlueColor] forState:UIControlStateNormal];
    button.titleLabel.font = self.buttonFont;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    [button setBackgroundColor:[UIColor colorWithRGBHex:0xf5f5f5]];
    button.layer.cornerRadius = 5.f;
    [self.contentView addSubview:button];
    return button;
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)configureWithInteraction:(OWSContactOffersInteraction *)interaction;
{
    OWSAssert(interaction);

    _interaction = interaction;

    OWSAssert(
        interaction.hasBlockOffer || interaction.hasAddToContactsOffer || interaction.hasAddToProfileWhitelistOffer);

    [self setNeedsLayout];
}

- (UIFont *)titleFont
{
    return [UIFont ows_mediumFontWithSize:16.f];
}

- (UIFont *)buttonFont
{
    return [UIFont ows_regularFontWithSize:14.f];
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

- (void)setFrame:(CGRect)frame
{
    BOOL needsLayout = !CGSizeEqualToSize(frame.size, self.frame.size);
    [super setFrame:frame];

    if (needsLayout) {
        [self layoutSubviews];
    }
}

- (void)setBounds:(CGRect)bounds
{
    BOOL needsLayout = !CGSizeEqualToSize(bounds.size, self.bounds.size);
    [super setBounds:bounds];

    if (needsLayout) {
        [self layoutSubviews];
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    // JSQ won't
    CGFloat contentWidth = floor(MIN(self.contentView.width, self.width - 2 * self.contentView.left));

    DDLogError(@"---- %f %f %f %f", self.width, self.contentView.width, contentWidth, self.contentView.left);

    CGRect titleFrame = self.contentView.bounds;
    titleFrame.origin = CGPointMake(self.hMargin, self.topVMargin);
    titleFrame.size.width = contentWidth - 2 * self.hMargin;
    titleFrame.size.height = ceil([self.titleLabel sizeThatFits:CGSizeZero].height);
    self.titleLabel.frame = titleFrame;

    __block CGFloat y = round(self.titleLabel.bottom + self.buttonVSpacing);
    DDLogError(@"first y: %f", y);
    void (^layoutButton)(UIButton *, BOOL) = ^(UIButton *button, bool isVisible) {
        if (isVisible) {
            button.hidden = NO;

            button.frame = CGRectMake(round(self.hMargin),
                round(y),
                floor(contentWidth - 2 * self.hMargin),
                ceil([button sizeThatFits:CGSizeZero].height + self.buttonVPadding));
            y = round(button.bottom + self.buttonVSpacing);
        } else {
            button.hidden = YES;
        }
    };

    layoutButton(self.addToContactsButton, self.interaction.hasAddToContactsOffer);
    layoutButton(self.addToProfileWhitelistButton, self.interaction.hasAddToProfileWhitelistOffer);
    layoutButton(self.blockButton, self.interaction.hasBlockOffer);

    [self.contentView addRedBorder];
    [self.titleLabel addRedBorder];
    [self.addToContactsButton addRedBorder];
    [self.addToProfileWhitelistButton addRedBorder];
    [self.blockButton addRedBorder];
}

- (CGSize)bubbleSizeForInteraction:(OWSContactOffersInteraction *)interaction
               collectionViewWidth:(CGFloat)collectionViewWidth
{
    CGSize result = CGSizeMake(collectionViewWidth, 0);
    result.height += self.topVMargin;
    result.height += self.bottomVMargin;

    result.height += ceil([self.titleLabel sizeThatFits:CGSizeZero].height);

    int buttonCount = ((interaction.hasBlockOffer ? 1 : 0) + (interaction.hasAddToContactsOffer ? 1 : 0)
        + (interaction.hasAddToProfileWhitelistOffer ? 1 : 0));
    result.height += buttonCount
        * (self.buttonVPadding + self.buttonVSpacing + ceil([self.addToContactsButton sizeThatFits:CGSizeZero].height));

    return result;
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    self.interaction = nil;
}

#pragma mark - Gesture recognizers

- (void)handleTapGesture:(UITapGestureRecognizer *)sender
{
    OWSAssert(self.interaction);

    if (sender.state == UIGestureRecognizerStateRecognized) {
        //        [self.systemMessageCellDelegate didTapSystemMessageWithInteraction:self.interaction];
    }
}

#pragma mark - Logging

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

@end

NS_ASSUME_NONNULL_END
