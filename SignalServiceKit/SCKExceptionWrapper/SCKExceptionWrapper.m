//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SCKExceptionWrapper.h"

NS_ASSUME_NONNULL_BEGIN

NSErrorDomain const SCKExceptionWrapperErrorDomain = @"SignalServiceKit.SCKExceptionWrapper";
NSErrorUserInfoKey const SCKExceptionWrapperUnderlyingExceptionKey = @"SCKExceptionWrapperUnderlyingException";

NSError *SCKExceptionWrapperErrorMake(NSException *exception)
{
    return [NSError errorWithDomain:SCKExceptionWrapperErrorDomain
                               code:SCKExceptionWrapperErrorThrown
                           userInfo:@ { SCKExceptionWrapperUnderlyingExceptionKey : exception }];
}

@implementation SCKExceptionWrapper

+ (BOOL)tryBlock:(void (^)(void))block error:(NSError **)outError
{
    OWSAssertDebug(outError);
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (outError) {
            *outError = SCKExceptionWrapperErrorMake(exception);
        }
        return NO;
    }
}

@end

void SCKRaiseIfExceptionWrapperError(NSError *_Nullable error)
{
    if (error && [error.domain isEqualToString:SCKExceptionWrapperErrorDomain]
        && error.code == SCKExceptionWrapperErrorThrown) {
        NSException *_Nullable exception = error.userInfo[SCKExceptionWrapperUnderlyingExceptionKey];
        OWSCPrecondition(exception);
        @throw exception;
    }
}

NS_ASSUME_NONNULL_END
