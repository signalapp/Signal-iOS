#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

#import "YapDatabaseExtension.h"

#import "YapDatabaseCloudKitTypes.h"
#import "YapDatabaseCloudKitOptions.h"
#import "YapDatabaseCloudKitConnection.h"
#import "YapDatabaseCloudKitTransaction.h"

#import "YDBCKChangeSet.h"
#import "YDBCKMergeInfo.h"
#import "YDBCKRecordInfo.h"
#import "YDBCKRecord.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const YapDatabaseCloudKitSuspendCountChangedNotification;
extern NSString *const YapDatabaseCloudKitInFlightChangeSetChangedNotification;

/**
 * Welcome to YapDatabase!
 *
 * https://github.com/yapstudios/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * YapDatabaseCloudKit is an extension that allows you to sync
 * objects in YapDatabase with Apple's CloudKit service.
 *
 * For the full documentation on Views, please see the related wiki article:
 * https://github.com/yapstudios/YapDatabase/wiki/YapDatabaseCloudKit
**/
@interface YapDatabaseCloudKit : YapDatabaseExtension


- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)mergeBlock
                  operationErrorBlock:(YapDatabaseCloudKitOperationErrorBlock)opErrorBlock;

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)mergeBlock
                  operationErrorBlock:(YapDatabaseCloudKitOperationErrorBlock)opErrorBlock
                           versionTag:(nullable NSString *)versionTag
                          versionInfo:(nullable id)versionInfo;

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)mergeBlock
                  operationErrorBlock:(YapDatabaseCloudKitOperationErrorBlock)opErrorBlock
                           versionTag:(nullable NSString *)versionTag
                          versionInfo:(nullable id)versionInfo
                              options:(nullable YapDatabaseCloudKitOptions *)options;

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)mergeBlock
                  operationErrorBlock:(YapDatabaseCloudKitOperationErrorBlock)opErrorBlock
              databaseIdentifierBlock:(nullable YapDatabaseCloudKitDatabaseIdentifierBlock)databaseIdentifierBlock
                           versionTag:(nullable NSString *)versionTag
                          versionInfo:(nullable id)versionInfo
                              options:(nullable YapDatabaseCloudKitOptions *)options;

@property (nonatomic, strong, readonly) YapDatabaseCloudKitRecordHandler *recordHandler;
@property (nonatomic, strong, readonly) YapDatabaseCloudKitMergeBlock mergeBlock;
@property (nonatomic, strong, readonly) YapDatabaseCloudKitOperationErrorBlock operationErrorBlock;

@property (nonatomic, copy, readonly) NSString *versionTag;

@property (nonatomic, copy, readonly) YapDatabaseCloudKitOptions *options;

#pragma mark Suspend & Resume

/**
 * Returns YES if the upload operation queue is suspended.
 * 
 * @see suspend
 * @see resume
**/
@property (atomic, readonly) BOOL isSuspended;

/**
 * Returns the current suspendCount.
 * If the suspendCount is zero, that means isSuspended == NO;
 * if the suspendCount is non-zero, that means isSuspended == YES;
 * 
 * @see suspend
 * @see resume
**/
@property (atomic, readonly) NSUInteger suspendCount;

/**
 * Before the CloudKit stack can begin pushing changes to the cloud, there are generally several steps that
 * must be taken first. These include general configuration steps, as well as querying the server to
 * pull down changes from other devices that occurred while the app was offline.
 *
 * Some example steps that may need to be performed prior to taking the extension "online":
 * - registering for push notifications
 * - creating the needed CKRecordZone's (if needed)
 * - creating the zone subscriptions (if needed)
 * - pulling changes via CKFetchRecordChangesOperation
 * 
 * It's important that all these tasks get completed before the YapDatabaseCloudKit extension begins attempting
 * to push data to the cloud. For example, if the proper CKRecordZone's haven't been created yet, then attempting
 * to insert objects into those missing zones will fail. And if, after after being offline, we begin pushing our
 * changes to the server before we pull others' changes, then we'll likely just get a bunch of failures & conflicts.
 * Not to mention waste a lot of bandwidth in the process.
 * 
 * For this reason, there is a flexible mechanism to "suspend" the upload process.
 *
 * That is, if YapDatabaseCloudKit is "suspended", it still remains fully functional.
 * That is, it's still "listening" for changes in the database, and invoking the recordHandler block to track
 * changes to CKRecord's, etc. However, while suspended, it operates in a slightly different mode, wherein it
 * it only QUEUES its CKModifyRecords operations. (It suspends its internal master operationQueue.) And where it
 * may dynamically modify its pending queue in response to merges and continued changes to the database.
 * 
 * You MUST match every call to suspend with a matching call to resume.
 * For example, if you invoke suspend 3 times, then the extension won't resume until you've invoked resume 3 times.
 *
 * Use this to your advantage if you have multiple tasks to complete before you want to resume the extension.
 * From the example above, one would create and register the extension as usual when setting up YapDatabase
 * and all the normal extensions needed by the app. However, they would invoke the suspend method 3 times before
 * registering the extension with the database. And then, as each of the 3 required steps complete, they would
 * invoke the resume method. Therefore, the extension will be available immediately to start monitoring for changes
 * in the database. However, it won't start pushing any changes to the cloud until the 3 required step
 * have all completed.
 * 
 * @return
 *   The current suspend count.
 *   This will be 1 if the extension was previously active, and is now suspended due to this call.
 *   Otherwise it will be greater than one, meaning it was previously suspended,
 *   and you just incremented the suspend count.
**/
- (NSUInteger)suspend;

/**
 * This method operates the same as invoking the suspend method the given number of times.
 * That is, it increments the suspend count by the given number.
 * 
 * You can invoke this method with a zero parameter in order to obtain the current suspend count, without modifying it.
 * 
 * @see suspend
**/
- (NSUInteger)suspendWithCount:(NSUInteger)suspendCountIncrement;

/**
 * See the suspend method for a description of the suspend/resume architecture.
 * 
 * @return
 *   The current suspend count.
 *   This will be 0 if the extension was previously suspended, and is now resumed due to this call.
 *   Otherwise it will be greater than one, meaning it's still suspended,
 *   and you just decremented the suspend count.
**/
- (NSUInteger)resume;

#pragma mark Change-Sets

/**
 * Returns the "current" changeSet,
 * which is either the inFlightChangeSet, or the next changeSet to go inFlight once resumed.
 *
 * In other words, the first YDBCKChangeSet in the queue.
**/
- (YDBCKChangeSet *)currentChangeSet;

/**
 * Returns an array of YDBCKChangeSet objects, which represent the pending (and in-flight) change-sets.
 * The array is ordered, such that:
 * - the first item in the array is either in-flight or the next to be uploaded
 * - the last item in the array represents the most recent change-set
 * 
 * From this array you'll be able to see exactly what YapDatabaseCloudKit is uploading (or intends to upload).
 * 
 * This is also useful if you want to perform a "dry run" test.
 * You can simply run a few tests with a debug database,
 * and keep the YapDatabaseCloudKit extension suspended the whole time.
 * Then just inspect the change-sets to ensure that everything is working as you expect.
**/
- (NSArray<YDBCKChangeSet *> *)pendingChangeSets;

/**
 * Faster access if you just want to get the counts.
 * 
 * - numberOfInFlightChangeSets:
 *     YDBCKChangeSets that have been dispatched to CloudKit Framework.
 *     These may or may not succeed, depending upon network conditions & other factors.
 *
 * - numberOfQueuedChangeSets:
 *     YDBCKChangeSets that have not been dispatched to CloudKit Framework.
 *     They are waiting for the current inFlight change-sets to succeed, or for YDBCK to be resumed.
 *
 * - numberOfPendingChangeSets:
 *     Includes all YDBCKChangeSets, both inFlight & queued.
 * 
 * In mathematical notion, the relationships are:
 * 
 * numberOfInFlightChangeSets == numberOfPendingChangeSets  - numberOfQueuedChangeSets
 * numberOfQueuedChangeSets   == numberOfPendingChangeSets  - numberOfInFlightChangeSets
 * numberOfPendingChangeSets  == numberOfInFlightChangeSets + numberOfQueuedChangeSets
**/
@property (atomic, readonly) NSUInteger numberOfInFlightChangeSets;
@property (atomic, readonly) NSUInteger numberOfQueuedChangeSets;
@property (atomic, readonly) NSUInteger numberOfPendingChangeSets;

/**
 * Atomic access to all counts at once.
**/
- (void)getNumberOfInFlightChangeSets:(NSUInteger *)numInFlightChangeSetsPtr
                     queuedChangeSets:(NSUInteger *)numQueuedChangeSetsPtr;

@end

NS_ASSUME_NONNULL_END
