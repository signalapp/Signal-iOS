//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/NSString+SSK.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (OWS)

- (NSString *)rtlSafeAppend:(NSString *)string referenceView:(UIView *)referenceView;
- (NSString *)rtlSafeAppend:(NSString *)string isRTL:(BOOL)isRTL;

- (NSString *)digitsOnly;

@end

NS_ASSUME_NONNULL_END
