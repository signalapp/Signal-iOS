//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSVerifyCodeRequest : TSRequest

@property (nonatomic, readonly) NSString *numberToValidate;

- (instancetype)init NS_UNAVAILABLE;

- (TSRequest *)initWithVerificationCode:(NSString *)verificationCode
                              forNumber:(NSString *)phoneNumber
                                    pin:(nullable NSString *)pin
                           signalingKey:(NSString *)signalingKey
                                authKey:(NSString *)authKey;

@end

NS_ASSUME_NONNULL_END
