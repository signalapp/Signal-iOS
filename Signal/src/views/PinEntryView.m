//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "PinEntryView.h"
#import "Signal-Swift.h"
#import <SignalUI/UIFont+OWS.h>
#import <SignalUI/UIView+SignalUI.h>
#import <SignalUI/ViewControllerUtils.h>

NS_ASSUME_NONNULL_BEGIN

@interface PinEntryView () <UITextFieldDelegate>

@property (nonatomic) UITextField *pinTextfield;
@property (nonatomic) OWSFlatButton *submitButton;
@property (nonatomic) UILabel *instructionsLabel;

@end

@implementation PinEntryView : UIView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (!self) {
        return self;
    }

    [self createContents];

    return self;
}

#pragma mark - view creation
- (UIFont *)labelFont
{
    return [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(14.f, 16.f)];
}

- (UIFont *)boldLabelFont
{
    return [UIFont ows_semiboldFontWithSize:ScaleFromIPhone5To7Plus(14.f, 16.f)];
}

- (UILabel *)createLabelWithText:(nullable NSString *)text
{
    UILabel *label = [UILabel new];
    label.textColor = Theme.primaryTextColor;
    label.text = text;
    label.font = self.labelFont;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textAlignment = NSTextAlignmentCenter;
    [self addSubview:label];
    return label;
}

- (void)createPinTextfield
{
    if (UIDevice.currentDevice.isIPhone5OrShorter) {
        self.pinTextfield = [DismissableTextField new];
    } else {
        self.pinTextfield = [OWSTextField new];
    }

    self.pinTextfield.textColor = Theme.primaryTextColor;
    self.pinTextfield.font = [UIFont ows_semiboldFontWithSize:ScaleFromIPhone5To7Plus(30.f, 36.f)];
    self.pinTextfield.textAlignment = NSTextAlignmentCenter;
    self.pinTextfield.keyboardType = UIKeyboardTypeNumberPad;
    self.pinTextfield.delegate = self;
    self.pinTextfield.secureTextEntry = YES;
    self.pinTextfield.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.pinTextfield];
}

- (UILabel *)createForgotLink
{
    UILabel *label = [UILabel new];
    label.textColor = Theme.accentBlueColor;
    NSString *text = NSLocalizedString(
        @"REGISTER_2FA_FORGOT_PIN", @"Label for 'I forgot my PIN' link in the 2FA registration view.");
    label.attributedText = [[NSAttributedString alloc]
        initWithString:text
            attributes:@{
                NSForegroundColorAttributeName : Theme.accentBlueColor,
                NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid)
            }];
    label.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(14.f, 16.f)];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textAlignment = NSTextAlignmentCenter;
    label.userInteractionEnabled = YES;
    [label addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                        action:@selector(forgotPinLinkTapped:)]];
    [self addSubview:label];
    return label;
}

- (void)createSubmitButton
{
    const CGFloat kSubmitButtonHeight = 47.f;
    // NOTE: We use ows_accentBlueColor instead of ows_accentBlueColor
    //       throughout the onboarding flow to be consistent with the headers.
    OWSFlatButton *submitButton =
        [OWSFlatButton buttonWithTitle:NSLocalizedString(@"REGISTER_2FA_SUBMIT_BUTTON",
                                           @"Label for 'submit' button in the 2FA registration view.")
                                  font:[OWSFlatButton fontForHeight:kSubmitButtonHeight]
                            titleColor:[UIColor whiteColor]
                       backgroundColor:UIColor.ows_accentBlueColor
                                target:self
                              selector:@selector(submitButtonWasPressed)];
    self.submitButton = submitButton;
    [self addSubview:submitButton];
    [self.submitButton autoSetDimension:ALDimensionHeight toSize:kSubmitButtonHeight];
}

- (nullable NSString *)instructionsText
{
    return self.instructionsLabel.text;
}

- (void)setInstructionsText:(nullable NSString *)instructionsText
{
    self.instructionsLabel.text = instructionsText;
}

- (nullable NSAttributedString *)attributedInstructionsText
{
    return self.instructionsLabel.attributedText;
}

- (void)setAttributedInstructionsText:(nullable NSAttributedString *)attributedInstructionsText
{
    self.instructionsLabel.attributedText = attributedInstructionsText;
}

- (void)createContents
{
    const CGFloat kVSpacing = ScaleFromIPhone5To7Plus(12, 30);

    UILabel *instructionsLabel = [self createLabelWithText:nil];
    self.instructionsLabel = instructionsLabel;
    [instructionsLabel autoPinTopToSuperviewMarginWithInset:kVSpacing];
    [instructionsLabel autoPinWidthToSuperview];

    UILabel *createForgotLink = [self createForgotLink];
    [createForgotLink autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:instructionsLabel withOffset:5];
    [createForgotLink autoPinWidthToSuperview];

    [self createPinTextfield];
    [self.pinTextfield autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:createForgotLink withOffset:kVSpacing];
    [self.pinTextfield autoPinWidthToSuperview];

    UIView *underscoreView = [UIView new];
    underscoreView.backgroundColor = [UIColor colorWithWhite:0.5 alpha:1.f];
    [self addSubview:underscoreView];
    [underscoreView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.pinTextfield withOffset:3];
    [underscoreView autoPinWidthToSuperview];
    [underscoreView autoSetDimension:ALDimensionHeight toSize:1.f];

    [self createSubmitButton];
    [self.submitButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:underscoreView withOffset:kVSpacing];
    [self.submitButton autoPinWidthToSuperview];
    [self updateIsSubmitEnabled];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
{

    [ViewControllerUtils ows2FAPINTextField:textField
              shouldChangeCharactersInRange:range
                          replacementString:insertionText];

    [self updateIsSubmitEnabled];

    if (self.delegate && [self.delegate respondsToSelector:@selector(pinEntryView:pinCodeDidChange:)]) {
        [self.delegate pinEntryView:self pinCodeDidChange:textField.text];
    }

    return NO;
}

- (void)updateIsSubmitEnabled
{
    [self.submitButton setEnabled:self.hasValidPin];
}

- (BOOL)makePinTextFieldFirstResponder
{
    return [self.pinTextfield becomeFirstResponder];
}

- (BOOL)hasValidPin
{
    return self.pinTextfield.text.length >= kMin2FAPinLength;
}

- (void)clearText
{
    self.pinTextfield.text = @"";
    [self updateIsSubmitEnabled];
}

#pragma mark - Events

- (void)submitButtonWasPressed
{
    [self.delegate pinEntryView:self submittedPinCode:self.pinTextfield.text];
}

- (void)forgotPinLinkTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self.delegate pinEntryViewForgotPinLinkTapped:self];
    }
}


@end

NS_ASSUME_NONNULL_END
