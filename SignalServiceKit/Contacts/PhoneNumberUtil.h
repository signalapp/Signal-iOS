//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <libPhoneNumber_iOS/NBPhoneNumberUtil.h>

NS_ASSUME_NONNULL_BEGIN

@class PhoneNumberUtilSwiftValues;

@interface PhoneNumberUtil : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSwiftValues:(PhoneNumberUtilSwiftValues *)swiftValues NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) PhoneNumberUtilSwiftValues *swiftValues;

+ (NSUInteger)translateCursorPosition:(NSUInteger)offset
                                 from:(NSString *)source
                                   to:(NSString *)target
                    stickingRightward:(bool)preferHigh;

+ (nullable NBPhoneNumber *)getExampleNumberForType:(NSString *)regionCode
                                               type:(NBEPhoneNumberType)type
                                  nbPhoneNumberUtil:(NBPhoneNumberUtil *)nbPhoneNumberUtil;

@end

NS_ASSUME_NONNULL_END
