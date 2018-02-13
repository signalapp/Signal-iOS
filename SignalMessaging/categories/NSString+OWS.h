//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSString (OWS)

- (NSString *)ows_stripped;

- (NSString *)rtlSafeAppend:(NSString *)string referenceView:(UIView *)referenceView;
- (NSString *)rtlSafeAppend:(NSString *)string isRTL:(BOOL)isRTL;

- (NSString *)digitsOnly;

@end

NS_ASSUME_NONNULL_END
