#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

#import "YapDatabaseExtension.h"
#import "YapDatabaseCloudKitTypes.h"
#import "YapDatabaseCloudKitOptions.h"
#import "YapDatabaseCloudKitConnection.h"
#import "YapDatabaseCloudKitTransaction.h"


@interface YapDatabaseCloudKit : YapDatabaseExtension

/**
 * 
**/
- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)mergeBlock
                        conflictBlock:(YapDatabaseCloudKitConflictBlock)conflictBlock;

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)mergeBlock
                        conflictBlock:(YapDatabaseCloudKitConflictBlock)conflictBlock
                           versionTag:(NSString *)versionTag;

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)mergeBlock
                        conflictBlock:(YapDatabaseCloudKitConflictBlock)conflictBlock
                           versionTag:(NSString *)versionTag
                              options:(YapDatabaseCloudKitOptions *)options;

- (instancetype)initWithRecordHandler:(YapDatabaseCloudKitRecordHandler *)recordHandler
                           mergeBlock:(YapDatabaseCloudKitMergeBlock)mergeBlock
                        conflictBlock:(YapDatabaseCloudKitConflictBlock)conflictBlock
                        databaseBlock:(YapDatabaseCloudKitDatabaseBlock)databaseBlock
                           versionTag:(NSString *)versionTag
                              options:(YapDatabaseCloudKitOptions *)options;

@property (nonatomic, strong, readonly) YapDatabaseCloudKitRecordBlock recordBlock;
@property (nonatomic, assign, readonly) YapDatabaseCloudKitBlockType recordBlockType;

@property (nonatomic, strong, readonly) YapDatabaseCloudKitMergeBlock mergeBlock;
@property (nonatomic, strong, readonly) YapDatabaseCloudKitConflictBlock conflictBlock;

@property (nonatomic, copy, readonly) NSString *versionTag;

@property (nonatomic, copy, readonly) YapDatabaseCloudKitOptions *options;

/**
 * Returns YES if the upload operation queue is suspended.
 * 
 * @see suspend
 * @see resume
**/
@property (atomic, readonly) BOOL isSuspended;

/**
 * Before the CloudKit stack is ready to use, often times there are configurations that must happen first.
 * For example:
 * - registering for push notifications
 * - creating the needed CKRecordZone's (if needed)
 * - creating the zone subscriptions (if needed)
 * 
 * It's important that all these tasks get completed before the YapDatabaseCloudKit extension begins attempting
 * to push data to the cloud. For that reason, there is a flexible mechanism to "suspend" the upload process.
 *
 * That is, if YapDatabaseCloudKit is "suspended", it still remains fully functional (listening for changes
 * in the database, and invoking the recordHandler block to track changes to CKRecord's, etc).
 * However it only QUEUES its CKModifyRecords operations. (It suspends its internal master operationQueue.)
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
 * See the suspend method for a description of the suspend/resume architecture.
 * 
 * @return
 *   The current suspend count.
 *   This will be 0 if the extension was previously suspended, and is now resumed due to this call.
 *   Otherwise it will be greater than one, meaning it's still suspended,
 *   and you just decremented the suspend count.
**/
- (NSUInteger)resume;

@end
