//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSLabel.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSLabel ()

@property (nonatomic, nullable) NSValue *cachedSize;

@end

#pragma mark -

@implementation OWSLabel

- (void)setText:(nullable NSString *)text
{
    if ([NSObject isNullableObject:text equalTo:self.text]) {
        return;
    }
    [super setText:text];
    self.cachedSize = nil;
}

- (void)setAttributedText:(nullable NSAttributedString *)attributedText
{
    if ([NSObject isNullableObject:attributedText equalTo:self.attributedText]) {
        return;
    }
    [super setAttributedText:attributedText];
    self.cachedSize = nil;
}

- (void)setTextColor:(nullable UIColor *)textColor
{
    if ([NSObject isNullableObject:textColor equalTo:self.textColor]) {
        return;
    }
    [super setTextColor:textColor];
    // No need to clear cached size here.
}

- (void)setFont:(nullable UIFont *)font
{
    if ([NSObject isNullableObject:font equalTo:self.font]) {
        return;
    }
    [super setFont:font];
    self.cachedSize = nil;
}

- (void)setLineBreakMode:(NSLineBreakMode)lineBreakMode
{
    if (self.lineBreakMode == lineBreakMode) {
        return;
    }
    [super setLineBreakMode:lineBreakMode];
    self.cachedSize = nil;
}

- (CGSize)sizeThatFits:(CGSize)size
{
    if (self.cachedSize) {
        return self.cachedSize.CGSizeValue;
    }
    CGSize result = [super sizeThatFits:size];
    self.cachedSize = [NSValue valueWithCGSize:result];
    return result;
}

@end

NS_ASSUME_NONNULL_END
