//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class PinEntryView;

@protocol PinEntryViewDelegate <NSObject>

- (void)pinEntryView:(PinEntryView *)entryView submittedPinCode:(NSString *)pinCode;
- (void)pinEntryViewForgotPinLinkTapped:(PinEntryView *)entryView;

@optional
- (void)pinEntryView:(PinEntryView *)entryView pinCodeDidChange:(NSString *)pinCode;

@end

@interface PinEntryView : UIView

@property (nonatomic, weak, nullable) id<PinEntryViewDelegate> delegate;
@property (nonatomic, readonly) BOOL hasValidPin;
@property (nullable, nonatomic) NSString *instructionsText;
@property (nullable, nonatomic) NSAttributedString *attributedInstructionsText;
@property (nonatomic, readonly) UIFont *boldLabelFont;

- (void)clearText;
- (BOOL)makePinTextFieldFirstResponder;

@end

NS_ASSUME_NONNULL_END
