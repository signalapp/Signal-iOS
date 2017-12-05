//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSAttributedString (OWS)

- (NSAttributedString *)rtlSafeAppend:(NSString *)text
                           attributes:(NSDictionary *)attributes
                        referenceView:(UIView *)referenceView;
- (NSAttributedString *)rtlSafeAppend:(NSAttributedString *)string referenceView:(UIView *)referenceView;

@end

NS_ASSUME_NONNULL_END
