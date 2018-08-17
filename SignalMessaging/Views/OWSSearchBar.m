//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSearchBar.h"
#import "OWSTextField.h"
#import "Theme.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/UIImage+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSearchBar () <UITextFieldDelegate, OWSTextFieldDelegate>

@property (nonatomic) OWSTextField *textField;

@property (nonatomic) UIButton *cancelButton;

@property (nonatomic) CAShapeLayer *pillboxLayer;
@property (nonatomic) OWSLayerView *pillboxView;

@property (nonatomic) UIButton *clearButton;
@property (nonatomic) UIImageView *searchIconView;

@property (nonatomic) UIStackView *contentStackView;

@end

#pragma mark -

@implementation OWSSearchBar

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self ows_configure];
    }

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) {
        [self ows_configure];
    }

    return self;
}

- (CGFloat)contentHMargin
{
    return 8.f;
}

- (CGFloat)contentVMargin
{
    return 10.f;
}

- (CGFloat)pillboxHMargin
{
    return 8.f;
}

- (CGFloat)pillboxVMargin
{
    return 7.f;
}

- (CGFloat)contentSpacing
{
    return 12.f;
}

- (CGFloat)pillboxSpacing
{
    return 8.f;
}

+ (CGFloat)pillboxRadius
{
    return 10.f;
}

- (CGSize)sizeThatFits:(CGSize)size
{
    // All that matters is the height.
    CGSize result = [self.textField sizeThatFits:CGSizeZero];
    result.width += self.pillboxHMargin * 2;
    result.height += self.pillboxVMargin * 2;
    result.width += self.contentHMargin * 2;
    result.height += self.contentVMargin * 2;
    return result;
}

- (void)ows_configure
{
    OWSAssert(!self.searchIconView);

    self.opaque = NO;
    self.backgroundColor = [UIColor clearColor];

    UIImage *_Nullable searchIcon = [UIImage imageNamed:@"searchbar_search"];
    searchIcon = [searchIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    OWSAssert(searchIcon);
    self.searchIconView = [[UIImageView alloc] initWithImage:searchIcon];
    [self.searchIconView setContentHuggingHigh];
    [self.searchIconView setCompressionResistanceHigh];

    UIImage *_Nullable clearIcon = [UIImage imageNamed:@"searchbar_clear"];
    clearIcon = [clearIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    OWSAssert(clearIcon);
    self.clearButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.clearButton setImage:clearIcon forState:UIControlStateNormal];
    [self.clearButton addTarget:self action:@selector(clearButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.clearButton setContentHuggingHigh];
    [self.clearButton setCompressionResistanceHigh];

    self.textField = [OWSTextField new];
    self.textField.font = [UIFont ows_dynamicTypeBodyFont];
    self.textField.delegate = self;
    self.textField.ows_delegate = self;
    self.textField.returnKeyType = UIReturnKeySearch;
    self.textField.enablesReturnKeyAutomatically = YES;
    [self.textField addTarget:self action:@selector(textDidChange:) forControlEvents:UIControlEventEditingChanged];
    [self.textField addTarget:self
                       action:@selector(textFieldReturnWasPressed:)
             forControlEvents:UIControlEventEditingDidEndOnExit];
    [self.textField setContentHuggingVerticalLow];
    [self.textField setContentHuggingVerticalHigh];
    [self.textField setCompressionResistanceHorizontalLow];
    [self.textField setCompressionResistanceVerticalHigh];

    UIStackView *pillboxStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.searchIconView,
        self.textField,
        self.clearButton,
    ]];
    pillboxStackView.spacing = self.pillboxSpacing;
    pillboxStackView.axis = UILayoutConstraintAxisHorizontal;
    pillboxStackView.alignment = UIStackViewAlignmentCenter;
    pillboxStackView.layoutMargins
        = UIEdgeInsetsMake(self.pillboxVMargin, self.pillboxHMargin, self.pillboxVMargin, self.pillboxHMargin);
    pillboxStackView.layoutMarginsRelativeArrangement = YES;

    self.cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.cancelButton setTitle:CommonStrings.cancelButton forState:UIControlStateNormal];
    self.cancelButton.titleLabel.font = UIFont.ows_dynamicTypeBodyFont;
    [self.cancelButton setContentHuggingHigh];
    [self.cancelButton setCompressionResistanceHigh];
    [self.cancelButton addTarget:self
                          action:@selector(cancelButtonPressed)
                forControlEvents:UIControlEventTouchUpInside];

    self.contentStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        pillboxStackView,
        self.cancelButton,
    ]];
    self.contentStackView.spacing = self.contentSpacing;
    self.contentStackView.axis = UILayoutConstraintAxisHorizontal;
    self.contentStackView.alignment = UIStackViewAlignmentCenter;
    [self addSubview:self.contentStackView];
    [self.contentStackView autoPinWidthToSuperviewWithMargin:self.contentHMargin];
    [self.contentStackView autoPinHeightToSuperviewWithMargin:self.contentVMargin];


    CAShapeLayer *pillboxLayer = [CAShapeLayer new];
    self.pillboxLayer = pillboxLayer;
    self.pillboxView = [[OWSLayerView alloc]
         initWithFrame:CGRectZero
        layoutCallback:^(UIView *layerView) {
            pillboxLayer.path =
                [UIBezierPath bezierPathWithRoundedRect:layerView.bounds cornerRadius:OWSSearchBar.pillboxRadius]
                    .CGPath;
        }];
    self.pillboxView.userInteractionEnabled = NO;
    [self.pillboxView.layer addSublayer:pillboxLayer];
    [pillboxStackView addSubview:self.pillboxView];
    [self.pillboxView autoPinEdgesToSuperviewEdges];
    [self.pillboxView setContentHuggingLow];
    [self.pillboxView setCompressionResistanceLow];
    self.pillboxView.layer.zPosition = -1;

    self.userInteractionEnabled = YES;
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTapSearchBar:)]];

    [self ows_applyTheme];

    [self updateState];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange:)
                                                 name:ThemeDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)ows_applyTheme
{
    OWSAssertIsOnMainThread();

    self.searchIconView.tintColor = Theme.placeholderColor;
    self.clearButton.tintColor = Theme.placeholderColor;

    self.pillboxLayer.fillColor = Theme.offBackgroundColor.CGColor;

    self.textField.textColor = Theme.primaryColor;
    if (self.placeholder.length > 0) {
        self.textField.attributedPlaceholder =
            [[NSAttributedString alloc] initWithString:self.placeholder
                                            attributes:@{
                                                NSForegroundColorAttributeName : Theme.placeholderColor,
                                            }];
    }

    [self.cancelButton setTitleColor:Theme.primaryColor forState:UIControlStateNormal];
}

- (void)updateState
{
    self.cancelButton.hidden = (!self.textField.isFirstResponder && self.textField.text.length < 1);
    self.clearButton.hidden = self.textField.text.length < 1;
}

- (void)setPlaceholder:(nullable NSString *)placeholder
{
    self.textField.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:placeholder
                                        attributes:@{
                                            NSForegroundColorAttributeName : Theme.placeholderColor,
                                        }];
}

- (nullable NSString *)placeholder
{
    return self.textField.placeholder;
}

- (void)setText:(nullable NSString *)text
{
    self.textField.text = text;

    [self updateState];
}

- (nullable NSString *)text
{
    return self.textField.text;
}

- (BOOL)becomeFirstResponder
{
    return [self.textField becomeFirstResponder];
}

- (BOOL)resignFirstResponder
{
    return [self.textField resignFirstResponder];
}

#pragma mark - OWSTextFieldDelegate

- (void)textFieldDidBecomeFirstResponder:(OWSTextField *)textField
{
    [self updateState];

    if ([self.delegate respondsToSelector:@selector(searchBarDidBeginEditing:)]) {
        [self.delegate searchBarDidBeginEditing:self];
    }
}

- (void)textFieldDidResignFirstResponder:(OWSTextField *)textField
{
    [self updateState];
}

#pragma mark - Events

- (void)themeDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self ows_applyTheme];
}

- (void)textDidChange:(id)sender
{
    [self updateState];
    [self.delegate searchBar:self textDidChange:self.text];
}

- (void)textFieldReturnWasPressed:(id)sender
{
    [self.textField resignFirstResponder];
    [self updateState];
    [self.delegate searchBar:self returnWasPressed:self.text];
}

- (void)cancelButtonPressed
{
    self.text = nil;

    [self updateState];

    [self.delegate searchBar:self textDidChange:self.text];
}

- (void)clearButtonPressed
{
    self.text = nil;

    [self updateState];

    [self.delegate searchBar:self textDidChange:self.text];
}

- (void)didTapSearchBar:(UIGestureRecognizer *)sender
{
    [self becomeFirstResponder];
}

@end

NS_ASSUME_NONNULL_END
