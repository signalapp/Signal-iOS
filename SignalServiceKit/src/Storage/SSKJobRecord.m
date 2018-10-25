//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SSKJobRecord.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSErrorDomain const SSKJobRecordErrorDomain = @"SignalServiceKit.JobRecord";

#pragma mark -
@interface SSKJobRecord ()

@property (nonatomic) SSKJobRecordStatus status;
@property (nonatomic) UInt64 sortId;

@end

@implementation SSKJobRecord

- (instancetype)initWithLabel:(NSString *)label
{
    self = [super init];
    if (!self) {
        return self;
    }

    _status = SSKJobRecordStatus_Ready;
    _label = label;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

#pragma mark - TSYapDatabaseObject Overrides

+ (NSString *)collection
{
    // To avoid a plethora of identical JobRecord subclasses, all job records share
    // a common collection and JobQueue's distinguish their behavior by the job's
    // `label`
    return @"JobRecord";
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    if (self.sortId == 0) {
        self.sortId = [SSKIncrementingIdFinder nextIdWithKey:self.class.collection transaction:transaction];
    }
    [super saveWithTransaction:transaction];
}

#pragma mark -

- (BOOL)saveAsStartedWithTransaction:(YapDatabaseReadWriteTransaction *)transaction error:(NSError **)outError
{
    if (self.status != SSKJobRecordStatus_Ready) {
        *outError =
            [NSError errorWithDomain:SSKJobRecordErrorDomain code:JobRecordError_IllegalStateTransition userInfo:nil];
        return NO;
    }
    self.status = SSKJobRecordStatus_Running;
    [self saveWithTransaction:transaction];

    return YES;
}

- (void)saveAsPermanentlyFailedWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    self.status = SSKJobRecordStatus_PermanentlyFailed;
    [self saveWithTransaction:transaction];
}

- (void)saveAsObsoleteWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    self.status = SSKJobRecordStatus_Obsolete;
    [self saveWithTransaction:transaction];
}

- (BOOL)saveRunningAsReadyWithTransaction:(YapDatabaseReadWriteTransaction *)transaction error:(NSError **)outError
{
    switch (self.status) {
        case SSKJobRecordStatus_Running: {
            self.status = SSKJobRecordStatus_Ready;
            [self saveWithTransaction:transaction];
            return YES;
        }
        case SSKJobRecordStatus_Ready:
        case SSKJobRecordStatus_PermanentlyFailed:
        case SSKJobRecordStatus_Obsolete:
        case SSKJobRecordStatus_Unknown: {
            *outError = [NSError errorWithDomain:SSKJobRecordErrorDomain
                                            code:JobRecordError_IllegalStateTransition
                                        userInfo:nil];
            return NO;
        }
    }
}

- (BOOL)addFailureWithWithTransaction:(YapDatabaseReadWriteTransaction *)transaction error:(NSError **)outError
{
    switch (self.status) {
        case SSKJobRecordStatus_Running: {
            self.failureCount++;
            [self saveWithTransaction:transaction];
            return YES;
        }
        case SSKJobRecordStatus_Ready:
        case SSKJobRecordStatus_PermanentlyFailed:
        case SSKJobRecordStatus_Obsolete:
        case SSKJobRecordStatus_Unknown: {
            *outError = [NSError errorWithDomain:SSKJobRecordErrorDomain
                                            code:JobRecordError_IllegalStateTransition
                                        userInfo:nil];
            return NO;
        }
    }
}

@end

NS_ASSUME_NONNULL_END
