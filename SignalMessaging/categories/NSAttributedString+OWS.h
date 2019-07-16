//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSAttributedString (OWS)

- (NSAttributedString *)rtlSafeAppend:(NSString *)text attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes;
- (NSAttributedString *)rtlSafeAppend:(NSAttributedString *)string;

@end

NS_ASSUME_NONNULL_END
