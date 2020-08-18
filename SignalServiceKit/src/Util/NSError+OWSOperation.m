//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSOperation.h"
#import "TSNetworkManager.h"
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

static void *kNSError_MessageSender_IsRetryable = &kNSError_MessageSender_IsRetryable;
static void *kNSError_MessageSender_ShouldBeIgnoredForGroups = &kNSError_MessageSender_ShouldBeIgnoredForGroups;
static void *kNSError_MessageSender_IsFatal = &kNSError_MessageSender_IsFatal;

// isRetryable and isFatal are opposites but not redundant.
//
// If a group message send fails, the send will be retried if any of the errors were retryable UNLESS
// any of the errors were fatal.  Fatal errors trump retryable errors.

@implementation NSError (OWSOperation)

- (BOOL)isRetryable
{
    NSNumber *_Nullable value = self.userInfo[OWSOperationIsRetryableKey];
    if (value == nil) {
        value = objc_getAssociatedObject(self, kNSError_MessageSender_IsRetryable);
    }

    // This value should always be set for all errors by the time OWSOperation
    // queries it's value.  If not, default to retrying in production.
    if (value != nil) {
        return [value boolValue];
    }
    if (IsNetworkConnectivityFailure(self)) {
        // We can safely default to retrying network failures.
        OWSLogVerbose(@"Error without retry behavior specified: %@", self);
        return YES;
    }
    OWSFailDebug(@"Error without retry behavior specified: %@", self);
    // Default to retrying to be conservative.
    return YES;
}

- (void)setIsRetryable:(BOOL)value
{
    objc_setAssociatedObject(self, kNSError_MessageSender_IsRetryable, @(value), OBJC_ASSOCIATION_COPY);
}

- (BOOL)shouldBeIgnoredForGroups
{
    NSNumber *value = objc_getAssociatedObject(self, kNSError_MessageSender_ShouldBeIgnoredForGroups);
    // This value will NOT always be set for all errors by the time we query it's value.
    // Default to NOT ignoring.
    return value ? [value boolValue] : NO;
}

- (void)setShouldBeIgnoredForGroups:(BOOL)value
{
    objc_setAssociatedObject(self, kNSError_MessageSender_ShouldBeIgnoredForGroups, @(value), OBJC_ASSOCIATION_COPY);
}

- (BOOL)isFatal
{
    NSNumber *value = objc_getAssociatedObject(self, kNSError_MessageSender_IsFatal);
    // This value will NOT always be set for all errors by the time we query it's value.
    // Default to NOT fatal.
    return value ? [value boolValue] : NO;
}

- (void)setIsFatal:(BOOL)value
{
    objc_setAssociatedObject(self, kNSError_MessageSender_IsFatal, @(value), OBJC_ASSOCIATION_COPY);
}

@end

NS_ASSUME_NONNULL_END
