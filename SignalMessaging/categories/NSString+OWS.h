//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSString (OWS)

- (NSString *)ows_stripped;

- (NSString *)rtlSafeAppend:(NSString *)string referenceView:(UIView *)referenceView;

@end

NS_ASSUME_NONNULL_END
