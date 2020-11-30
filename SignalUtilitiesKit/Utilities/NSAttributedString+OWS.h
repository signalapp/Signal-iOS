//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSAttributedString (OWS)

- (NSAttributedString *)rtlSafeAppend:(NSString *)text attributes:(NSDictionary *)attributes;
- (NSAttributedString *)rtlSafeAppend:(NSAttributedString *)string;

@end

NS_ASSUME_NONNULL_END
