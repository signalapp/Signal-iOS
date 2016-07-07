/**
 * Copyright Deusty LLC.
**/

@class YapDatabaseCloudCorePipeline;
@class YapDatabaseCloudCoreOperation;


@protocol YapDatabaseCloudCorePipelineDelegate
@required

/**
 * This method is invoked when the operation is ready to be started (i.e. ready to start network IO).
 * 
 * The delegate should attempt to perform the corresponding network task.
 * 
 * If the network task completes, the delegate should:
 * - perform a readWriteTransaction on the database
 * - update any object(s) in the database (as needed)
 * - invoke [[transaction ext:MyCloudCore] completeOperation:operation]
 * 
 * This allows for updating your object(s) and deleting the operation from the queue in the same atomic commit.
 * 
 * In the event the network task fails, the delegate should generally give the operation back to the pipeline.
 * There are a few ways to accomplish this.
 *
 * If the network task failed due to an Internet disconnection, typically the delegate will:
 * - suspend the pipeline or parent YDBCloudCore instance (usually done from a manager class that monitors reachability)
 * - invoke [pipeline setStatusAsPendingForOperationUUID:operation.uuid]
 * 
 * Since the pipeline has been suspended, it won't be able to restart the operation until it's resumed.
 * Once resumed (presumably due to Internet reconnection) it will automatically re-start the operation
 * by invoking 'startOperation:withContext:forPipeline: again.
 * 
 * If the network task failed due to a rate-limiting error from the server, the delegate can:
 * - calculate a delay, possibly using an exponential backoff algorithm
 * - invoke [pipeline setStatusAsPendingForOperationUUID:operation.uuid withRetryDelay:delay]
 * 
 * The pipeline will use an internal timer to ensure the operation isn't started again until after the delay expires.
 * 
 * Tip: You can use the pipeline's ephemeralInfo dictionary to store a failCount for the operation,
 *      in order to calculate exponential backoff delay.
 * 
 * If the network task failed due to some unrecoverable error,
 * then it may be the case that the operation needs to be skipped.
 * In this case, the delegate will:
 * - perform a readWriteTransaction on the database
 * - update any object(s) in the database (as needed)
 * - invoke [[transaction ext:MyCloudCore] skipOperation:operation]
 * 
 * NOTE:
 *   The pipeline will attempt to start as many concurrent operations as it can.
 *   The number of concurrent operations is limited by:
 *   - pipeline.maxConcurrentOperationCount
 *   - the operations within the pipeline, and their corresponding dependencies
**/
- (void)startOperation:(YapDatabaseCloudCoreOperation *)operation forPipeline:(YapDatabaseCloudCorePipeline *)pipeline;

@end
