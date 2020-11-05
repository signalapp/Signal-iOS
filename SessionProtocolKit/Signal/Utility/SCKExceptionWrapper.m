//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SCKExceptionWrapper.h"
#import <SessionProtocolKit/OWSAsserts.h>

NS_ASSUME_NONNULL_BEGIN

NSErrorDomain const SCKExceptionWrapperErrorDomain = @"SignalCoreKit.SCKExceptionWrapper";
NSErrorUserInfoKey const SCKExceptionWrapperUnderlyingExceptionKey = @"SCKExceptionWrapperUnderlyingException";

NSError *SCKExceptionWrapperErrorMake(NSException *exception)
{
    return [NSError errorWithDomain:SCKExceptionWrapperErrorDomain
                               code:SCKExceptionWrapperErrorThrown
                           userInfo:@{ SCKExceptionWrapperUnderlyingExceptionKey : exception }];
}

@implementation SCKExceptionWrapper

+ (BOOL)tryBlock:(void (^)(void))block error:(NSError **)outError
{
    OWSAssertDebug(outError);
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        *outError = SCKExceptionWrapperErrorMake(exception);
        return NO;
    }
}

@end

void SCKRaiseIfExceptionWrapperError(NSError *_Nullable error)
{
    if (error && [error.domain isEqualToString:SCKExceptionWrapperErrorDomain]
        && error.code == SCKExceptionWrapperErrorThrown) {
        NSException *_Nullable exception = error.userInfo[SCKExceptionWrapperUnderlyingExceptionKey];
        OWSCAssert(exception);
        @throw exception;
    }
}

NS_ASSUME_NONNULL_END
