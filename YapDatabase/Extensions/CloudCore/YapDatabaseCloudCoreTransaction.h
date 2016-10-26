/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionTransaction.h"

@class YapDatabaseCloudCoreOperation;
@class YapDatabaseCloudCorePipeline;


@interface YapDatabaseCloudCoreTransaction : YapDatabaseExtensionTransaction

#pragma mark Operation Handling

/**
 * Allows you to queue an operation to be executed automatically by the appropriate pipeline.
 * This may be used as an alternative to creating an operation from within the YapDatabaseCloudCoreHandler.
 *
 * @param operation
 *   The operation to be added to the pipeline's queue.
 *   The operation.pipeline property specifies which pipeline to use.
 *   The operation will be added to a new graph for the current commit.
 *
 * @return
 *   NO if the operation isn't properly configured for use.
**/
- (BOOL)addOperation:(YapDatabaseCloudCoreOperation *)operation;

/**
 * Allows you to insert an operation into an existing graph.
 *
 * For example, say an operation in the currently executing graph (graphIdx = 0) fails due to some conflict.
 * And to resolve the conflict you need to:
 * - execute a different (new operation)
 * - and then re-try the failed operation
 *
 * What you can do is create & insert the new operation (into graphIdx zero).
 * And modify the old operation to depend on the new operation (@see 'modifyOperation').
 *
 * The dependency graph will automatically be recalculated using the inserted operation.
 *
 * @param operation
 *   The operation to be inserted into the pipeline's queue.
 *   The operation.pipeline property specifies which pipeline to use.
 *   The operation will be inserted into the graph corresponding to the graphIdx parameter.
 *
 * @param graphIdx
 *   The graph index for the corresponding pipeline.
 *   The currently executing graph index is always zero, which is the most common value.
 *
 * @return
 *   NO if the operation isn't properly configured for use.
**/
- (BOOL)insertOperation:(YapDatabaseCloudCoreOperation *)operation inGraph:(NSInteger)graphIdx;

/**
 * Replaces the existing operation with the new version.
 * 
 * The dependency graph will automatically be recalculated using the new operation version.
**/
- (BOOL)modifyOperation:(YapDatabaseCloudCoreOperation *)operation;

/**
 * This method MUST be invoked in order to mark an operation as complete.
 * 
 * Until an operation is marked as completed or skipped,
 * the pipeline will act as if the operation is still in progress.
 * And the only way to mark an operation as complete or skipped,
 * is to use either the `completeOperationWithUUID:` or one of the skipOperation methods.
 * These methods allow the system to remove the operation from its internal sqlite table.
**/
- (void)completeOperationWithUUID:(NSUUID *)operationUUID;
- (void)completeOperationWithUUID:(NSUUID *)operationUUID inPipeline:(NSString *)pipelineName;

/**
 * Use these methods to skip/abort operations.
 * 
 * Until an operation is marked as completed or skipped,
 * the pipeline will act as if the operation is still in progress.
 * And the only way to mark an operation as complete or skipped,
 * is to use either the `completeOperationWithUUID:` or one of the skipOperation methods.
 * These methods allow the system to remove the operation from its internal sqlite table.
**/
- (void)skipOperationWithUUID:(NSUUID *)operationUUID;
- (void)skipOperationWithUUID:(NSUUID *)operationUUID inPipeline:(NSString *)pipelineName;

- (void)skipOperationsPassingTest:(BOOL (^)(YapDatabaseCloudCorePipeline *pipeline,
                                            YapDatabaseCloudCoreOperation *operation,
                                            NSUInteger graphIdx, BOOL *stop))testBlock;

- (void)skipOperationsInPipeline:(NSString *)pipeline
                     passingTest:(BOOL (^)(YapDatabaseCloudCoreOperation *operation,
                                           NSUInteger graphIdx, BOOL *stop))testBlock;

#pragma mark Operation Searching

/**
 * Searches for an operation with the given UUID.
 * 
 * @return The corresponding operation, if found. Otherwise nil.
**/
- (YapDatabaseCloudCoreOperation *)operationWithUUID:(NSUUID *)uuid;

/**
 * Searches for an operation with the given UUID and pipeline.
 * If you know the pipeline, this method is a bit more efficient than 'operationWithUUID'.
 * 
 * @return The corresponding operation, if found. Otherwise nil.
**/
- (YapDatabaseCloudCoreOperation *)operationWithUUID:(NSUUID *)uuid inPipeline:(NSString *)pipelineName;

/**
 * @param operation
 *   The operation to search for.
 *   The operation.pipeline property specifies which pipeline to use.
 *
 * @return
 *   The index of the graph that contains the given operation.
 *   Or NSNotFound if a graph isn't found.
**/
- (NSUInteger)graphForOperation:(YapDatabaseCloudCoreOperation *)operation;

/**
 * Enumerates the queued operations.
 * 
 * This is useful for finding operation.
 * For example, you might use this to search for an upload operation with a certain cloudURI.
 *
 * Note:
 *   An identical method is available in YapDatabaseCloudCorePipeline.
 *   So a transaction isn't required to search for operations.
 *
 *   The only difference with this methods is, within the context of a read-write transaction,
 *   it will include added, inserted and modified operations.
 *   For example, if an operation has been modified within the read-write transaction,
 *   then you'll see the uncommitted modified version of the operation when enumerating.
 **/
- (void)enumerateOperationsUsingBlock:(void (^)(YapDatabaseCloudCorePipeline *pipeline,
                                                YapDatabaseCloudCoreOperation *operation,
                                                NSUInteger graphIdx, BOOL *stop))enumBlock;
/**
 * Enumerates the queued operations in a particluar pipeline.
 *
 * This is useful for finding operation.
 * For example, you might use this to search for an upload operation with a certain cloudURI.
 *
 * Note:
 *   An identical method is available in YapDatabaseCloudCorePipeline.
 *   So a transaction isn't required to search for operations.
 *
 *   The only difference with this methods is, within the context of a read-write transaction,
 *   it will include added, inserted and modified operations.
 *   For example, if an operation has been modified within the read-write transaction,
 *   then you'll see the uncommitted modified version of the operation when enumerating.
**/
- (void)enumerateOperationsInPipeline:(NSString *)pipeline
                      usingBlock:(void (^)(YapDatabaseCloudCoreOperation *operation,
                                           NSUInteger graphIdx, BOOL *stop))enumBlock;

#pragma mark Tag Support

/**
 * Returns the currently set tag for the given key/identifier tuple.
 *
 * @param key
 *   A unique identifier for the resource.
 *   E.g. the cloudURI for a remote file.
 *
 * @param identifier
 *   The type of tag being stored.
 *   E.g. "eTag", "globalFileID"
 *   If nil, the identifier is automatically converted to the empty string.
 *
 * @return
 *   The most recently assigned tag.
**/
- (id)tagForKey:(NSString *)key withIdentifier:(NSString *)identifier;

/**
 * Allows you to update the current tag value for the given key/identifier tuple.
 * 
 * @param tag
 *   The tag to store.
 *
 *   The following classes are supported:
 *   - NSString
 *   - NSNumber
 *   - NSData
 * 
 * @param key
 *   A unique identifier for the resource.
 *   E.g. the cloudURI for a remote file.
 * 
 * @param identifier
 *   The type of tag being stored.
 *   E.g. "eTag", "globalFileID"
 *   If nil, the identifier is automatically converted to the empty string.
 * 
 * If the given tag is nil, the effect is the same as invoking removeTagForKey:withIdentifier:.
 * If the given tag is an unsupported class, throws an exception.
**/
- (void)setTag:(id)tag forKey:(NSString *)key withIdentifier:(NSString *)identifier;

/**
 * Removes the tag for the given key/identifier tuple.
 * 
 * Note that this method only removes the specific key+identifier value.
 * If there are other tags with the same key, but different identifier, then those values will remain.
 * To remove all such values, use removeAllTagsForKey.
 *
 * @param key
 *   A unique identifier for the resource.
 *   E.g. the cloudURI for a remote file.
 * 
 * @param identifier
 *   The type of tag being stored.
 *   E.g. "eTag", "globalFileID"
 *   If nil, the identifier is automatically converted to the empty string.
 * 
 * @see removeAllTagsForCloudURI
**/
- (void)removeTagForKey:(NSString *)key withIdentifier:(NSString *)identifier;

/**
 * Removes all tags with the given key (matching any identifier).
**/
- (void)removeAllTagsForKey:(NSString *)key;

#pragma mark Attach / Detach Support

/**
 * The attach/detach mechanism works in a manner similar to retain/release.
 *
 * That is, when you attach a (local) collection/key tuple to a (remote) URI, it increments the "retainCount"
 * for the URI. And when you detach the collection/key tuple, then the "retainCount" for the URI is decremented.
 * 
 * Here are the rules:
 *
 * - You can attach a single collection/key tuple to multiple URIs.
 * - A single URI can be "retained" by multiple collection/key tuples.
 *   
 *   Thus there is a many-to-many mapping between collection/key tuples and URIs.
 *
 * - Attaching a collection/key tuple to the same URI multiple times only increments the retain count once.
 * - The same is true of detaching multiple times.
 * 
 *   In other words, when the attach method runs, it first checks to see if the {collection/key <-> URI} mapping
 *   already exists. If it does, then the attach request does nothing.
 *   And similarly, when the detach method runs, it first checks to see if the {collection/key <-> URI} mapping
 *   exists. And if it doesn't, then the detach request does nothing.
 * 
 * - An attempt to attach a collection/key tuple that doesn't exist will be queued for the duration
 *   of the readWriteTransaction.
 * - The attach will then automatically take place (take effect) when the corresponding collection/key is inserted
 *   (within the same readWriteTransaction).
 * 
 *   Thus you can issue an attach request immediately before the corresponding insert of the object.
 * 
 * This method only works if within a readWriteTrasaction.
 * Invoking this method from within a read-only transaction will throw an exception.
 *
 * @param cloudURI
 *   The URI for a remote file / record.
 *   This is typically the relative path of the file on the cloud server.
 *   E.g. "/documents/foo.bar"
 *   
 *   Note: The exact format of URI's is defined by the cloud domain. For example:
 *   - Dropbox may use a relative URL format. (/documents/foo.bar)
 *   - Apple's CloudKit may use URIs based upon CKRecordID.
 *
 * @param key
 *   The key of the row in YapDatabase
 *
 * @param collection
 *   The collection of the row in YapDatabase
**/
- (void)attachCloudURI:(NSString *)cloudURI
                forKey:(NSString *)key
          inCollection:(NSString *)collection;

/**
 * @param cloudURI
 *   The URI for a remote file / record.
 *   This is typically the relative path of the file on the cloud server.
 *   E.g. "/documents/foo.bar"
 *
 *   Note: The exact format of URI's is defined by the cloud domain. For example:
 *   - Dropbox may use a relative URL format. (/documents/foo.bar)
 *   - Apple's CloudKit may use URIs based upon CKRecordID.
 *
 * @param key
 *   The key of the row in YapDatabase
 * 
 * @param collection
 *   The collection of the row in YapDatabase
 * 
 * Important: This method only works if within a readWriteTrasaction.
 * Invoking this method from within a read-only transaction will throw an exception.
**/
- (void)detachCloudURI:(NSString *)cloudURI
                forKey:(NSString *)key
          inCollection:(NSString *)collection;

@end
