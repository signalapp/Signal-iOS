//
//  TSInvalidIdentityKeyErrorMessage.m
//  Signal
//
//  Created by Frederic Jacobs on 15/02/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeyErrorMessage.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSInvalidIdentityKeyErrorMessage

- (void)acceptNewIdentityKey
{
    NSAssert(NO, @"Method needs to be implemented in subclasses of TSInvalidIdentityKeyErrorMessage.");
}

- (NSString *)newIdentityKey
{
    NSAssert(NO, @"Method needs to be implemented in subclasses of TSInvalidIdentityKeyErrorMessage.");
    return nil;
}

- (NSString *)theirSignalId
{
    NSAssert(NO, @"Method needs to be implemented in subclasses of TSInvalidIdentityKeyErrorMessage.");
    return nil;
}

@end

NS_ASSUME_NONNULL_END
