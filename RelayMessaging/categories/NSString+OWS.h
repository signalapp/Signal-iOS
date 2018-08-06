//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <RelayServiceKit/NSString+SSK.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (OWS)

- (NSString *)rtlSafeAppend:(NSString *)string;

- (NSString *)digitsOnly;

@end

NS_ASSUME_NONNULL_END
