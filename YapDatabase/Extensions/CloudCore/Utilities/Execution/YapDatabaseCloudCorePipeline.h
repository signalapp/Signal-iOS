/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>

#import "YapDatabaseCloudCorePipelineDelegate.h"
#import "YapDatabaseCloudCoreGraph.h"
#import "YapDatabaseCloudCoreOperation.h"

typedef NS_ENUM(NSInteger, YDBCloudCoreOperationStatus) {
	
	/**
	 * Pending means that the operation is queued in the pipeline,
	 * and may be released to the delegate when ready.
	 * 
	 * If an operation fails, the PipelineDelegate may re-queue the operation by marking its status as pending.
	 * This gives control over the operation back to the pipeline,
	 * and it will dispatch it to the PipelineDelegate again when ready.
	**/
	YDBCloudOperationStatus_Pending = 0,
	
	/**
	 * The operation has been started.
	 * I.e. has been handed to the PipelineDelegate via 'startOperation::'.
	**/
	YDBCloudOperationStatus_Started,
	
	/**
	 * Until an operation is marked as either completed or skipped,
	 * the pipeline will act as if the operation is still in progress.
	 * 
	 * In order to mark an operation as completed or skipped, the following must be used:
	 * - [YapDatabaseCloudCoreTransaction completeOperation:]
	 * - [YapDatabaseCloudCoreTransaction skipOperation:]
	 * 
	 * These methods allow the system to delete the operation from the internal sqlite table.
	**/
	YDBCloudOperationStatus_Completed,
	YDBCloudOperationStatus_Skipped,
};

/**
 * This notification is posted whenever the operations in the pipeline's queue have changed.
 * That is, one of the following have occurred:
 * - One or more operations were removed from the queue (completed or skipped)
 * - One or more operations were added to the queue (added or inserted)
 * - One or more operations were modified
 * 
 * This notification is posted to the main thread.
**/
extern NSString *const YDBCloudCorePipelineQueueChangedNotification;

/**
 * This notification is posted whenever the suspendCount changes.
 * This notification is posted to the main thread.
**/
extern NSString *const YDBCloudCorePipelineSuspendCountChangedNotification;

/**
 * A "pipeline" represents a queue of operations for syncing with a cloud server.
 * It operates by managing a series of "graphs".
 * 
 * Generally speaking, a graph is all the cloud operations that were generated in a single commit (for a
 * specific pipeline). Within the graph are the various operations with their different dependencies & priorities.
 * The operations within a graph will be executed in accordance with the set dependencies & priorities.
 * 
 * The pipeline manages executing the operations within a graph.
 * It also ensures that graphs are completed in commit order.
 * 
 * That is, if a pipeline contains 2 graphs:
 * - graph "A" - representing operations from commit #32
 * - graph "B" - represending operations from commit #33
 * 
 * Then the pipeline will ensure that all operations from graphA complete before any operations from graphB start.
**/
@interface YapDatabaseCloudCorePipeline : NSObject

/**
 * Initializes a pipeline instance with the given name and delegate.
 * After creating a pipeline instance, you need to register it via [YapDatabaseCloudCore registerPipeline:].
**/
- (instancetype)initWithName:(NSString *)name delegate:(id <YapDatabaseCloudCorePipelineDelegate>)delegate;


@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, weak, readonly) id <YapDatabaseCloudCorePipelineDelegate> delegate;

#pragma mark Configuration

/**
 * If you decide to rename a pipeline, you should be sure to set the previousNames property.
 * This is to ensure that operations (from previous app launches) that were tagged with the previous pipeline name
 * can be properly migrated to the new pipeline name.
 * 
 * This property must be set before the pipeline is registered.
**/
@property (nonatomic, copy, readwrite) NSSet *previousNames;

/**
 * This value is the maximum number of operations that will be assigned to the delegate at any one time.
 * 
 * The pipeline keeps track of operations that have been assigned to the delegate (via startOperation:forPipeline:),
 * and will delay assigning any more operations once the maxConcurrentOperationCount has been reached.
 * Once an operation is completed (or skipped), the pipeline will automatically resume.
 * 
 * Of course, the delegate is welcome to perform its own concurrency restriction.
 * For example, via NSURLSessionConfiguration.HTTPMaximumConnectionsPerHost.
 * In which case it may simply set this to a high enough value that it won't interfere with its own implementation.
 * 
 * This value may be changed at anytime.
 *
 * The default value is 8.
**/
@property (atomic, assign, readwrite) NSUInteger maxConcurrentOperationCount;

#pragma mark Operation Searching

/**
 * Searches for an operation with the given UUID.
 *
 * @return The corresponding operation, if found. Otherwise nil.
**/
- (YapDatabaseCloudCoreOperation *)operationWithUUID:(NSUUID *)uuid;

/**
 * Enumerates the queued operations.
 *
 * This is useful for finding operation.
 * For example, you might use this to search for an upload operation with a certain cloudPath.
**/
- (void)enumerateOperationsUsingBlock:(void (^)(YapDatabaseCloudCoreOperation *operation,
                                                NSUInteger graphIdx, BOOL *stop))enumBlock;

/**
 * Returns the number of graphs queued in the pipeline.
 * Each graph represents the operations from a particular commit.
**/
- (NSUInteger)graphCount;

#pragma mark Operation Status

/**
 * Returns the current status for the given operation.
**/
- (YDBCloudCoreOperationStatus)statusForOperationWithUUID:(NSUUID *)opUUID;

/**
 * Typically you are strongly discouraged from manually starting an operation.
 * You should allow the pipeline to mange the queue, and only start operations when told to.
 *
 * However, there is one particular edge case in which is is unavoidable: background network tasks.
 * If the app is relaunched, and you discover there are network task from a previous app session,
 * you'll obviously want to avoid starting the corresponding operation again.
 * In this case, you should use this method to inform the pipeline that the operation is already started.
**/
- (void)setStatusAsStartedForOperationWithUUID:(NSUUID *)opUUID;

/**
 * The PipelineDelegate may invoke this method to reset a failed operation.
 * This gives control over the operation back to the pipeline,
 * and it will dispatch it back to the PipelineDelegate again when ready.
**/
- (void)setStatusAsPendingForOperationWithUUID:(NSUUID *)opUUID;

/**
 * The PipelineDelegate may invoke this method to reset a failed operation,
 * and simultaneously tell the pipeline to delay retrying it again for a period of time.
 *
 * This is typically used when implementing retry logic such as exponential backoff.
 * It works by setting a hold on the operation to [now dateByAddingTimeInterval:delay].
**/
- (void)setStatusAsPendingForOperationWithUUID:(NSUUID *)opUUID
                                    retryDelay:(NSTimeInterval)delay;

#pragma mark Operation Hold

/**
 * Returns the current hold for the operation, or nil if there is no hold.
**/
- (NSDate *)holdDateForOperationWithUUID:(NSUUID *)opUUID;

/**
 * And operation can be put on "hold" until a specified date.
 * This is typically used in conjunction with retry logic such as exponential backoff.
 * 
 * The operation won't be delegated again until the given date.
 * You can pass a nil date to remove a hold on an operation.
 * 
 * @see setStatusAsPendingForOperation:withRetryDelay:
**/
- (void)setHoldDate:(NSDate *)date forOperationWithUUID:(NSUUID *)opUUID;


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
 * Increments the suspendCount.
 * All calls to 'suspend' need to be matched with an equal number of calls to 'resume'.
 * 
 * @return
 *   The new suspend count.
 *   This will be 1 if the pipeline was previously active, and is now suspended due to this call.
 *   Otherwise it will be greater than one, meaning it was previously suspended,
 *   and you just incremented the suspend count.
 * 
 * @see resume
 * @see suspendCount
**/
- (NSUInteger)suspend;

/**
 * This method operates the same as invoking the suspend method the given number of times.
 * That is, it increments the suspend count by the given number.
 *
 * If you invoke this method with a zero parameter,
 * it will simply return the current suspend count, without modifying it.
 *
 * @see suspend
 * @see suspendCount
**/
- (NSUInteger)suspendWithCount:(NSUInteger)suspendCountIncrement;

/**
 * Decrements the suspendCount.
 * All calls to 'suspend' need to be matched with an equal number of calls to 'resume'.
 *
 * @return
 *   The current suspend count.
 *   This will be 0 if the extension was previously suspended, and is now resumed due to this call.
 *   Otherwise it will be greater than one, meaning it's still suspended,
 *   and you just decremented the suspend count.
 *
 * @see suspend
 * @see suspendCount
**/
- (NSUInteger)resume;

@end
