//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSString (OWS)

- (NSString *)rtlSafeAppend:(NSString *)string referenceView:(UIView *)referenceView;

@end

@interface NSAttributedString (OWS)

- (NSAttributedString *)rtlSafeAppend:(NSAttributedString *)string referenceView:(UIView *)referenceView;

@end

NS_ASSUME_NONNULL_END
