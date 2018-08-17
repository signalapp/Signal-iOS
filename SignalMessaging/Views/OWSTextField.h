//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSTextField;

@protocol OWSTextFieldDelegate <NSObject>

- (void)textFieldDidBecomeFirstResponder:(OWSTextField *)textField;
- (void)textFieldDidResignFirstResponder:(OWSTextField *)textField;

@end

#pragma mark -

@interface OWSTextField : UITextField

@property (nonatomic, weak) id<OWSTextFieldDelegate> ows_delegate;

@end

NS_ASSUME_NONNULL_END
