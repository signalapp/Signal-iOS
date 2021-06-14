//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSInvalidIdentityKeyErrorMessage.h>
#import <SignalServiceKit/OWSError.h>

NS_ASSUME_NONNULL_BEGIN

@implementation TSInvalidIdentityKeyErrorMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (void)throws_acceptNewIdentityKey
{
    OWSAbstractMethod();
}

- (BOOL)acceptNewIdentityKeyWithError:(NSError **)error
{
    @try {
        [self throws_acceptNewIdentityKey];
        return YES;
    } @catch (NSException *exception) {
        *error = OWSErrorMakeAssertionError(@"Error: %@", exception.debugDescription);
        return NO;
    }
}

- (nullable NSData *)throws_newIdentityKey
{
    OWSAbstractMethod();
    return nil;
}

- (SignalServiceAddress *)theirSignalAddress
{
    OWSAbstractMethod();
    return nil;
}

@end

NS_ASSUME_NONNULL_END
