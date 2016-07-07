/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>


/**
 * This is the base class for concrete subclasses such as FileOperations & RecordOperations.
 *
 * Do not directly create instances of this class.
 * Instead create instances of concrete subclass such as:
 * - YapDatabaseCloudCoreFileOperation
 * - YapDatabaseCloudCoreRecordOperation
**/
@interface YapDatabaseCloudCoreOperation : NSObject <NSCoding, NSCopying>

/**
 * Every operation has a randomly generated UUID.
 * This can be used for dependency references, or for uniquely identifying this specific operation.
**/
@property (nonatomic, readonly) NSUUID *uuid;

#pragma mark Configuration

/**
 * Every operation gets put into a single pipeline, which is in charge of scheduling & executing the operation.
 * 
 * You can choose to have the operation put into the default pipeline,
 * or you can choose to have it put into a custom pipeline by specifying the registered name of the desired pipeline.
 *
 * The default value is nil.
 *
 * If you set a pipeline value which doesn't match any registered pipelines (or you leave the value nil),
 * then the operation will be placed into the default pipeline.
 *
 * @see YapDatabaseOnwCloudPipeline
 * @see [YapDatabase registerPipeline]
 * 
 * Mutability:
 *   Before the operation has been handed over to YapDatabaseCloudCore, this property is mutable.
 *   However, once the operation has been handed over to YapDatabaseCloudCore, it becomes immutable.
**/
@property (nonatomic, copy, readwrite) NSString *pipeline;

/**
 * At the local level, when dealing with YapDatabase, you have the benefit of atomic transactions.
 * Thus you can make changes to multiple objects, and apply the changes in an atomic fashion.
 * However, the cloud server only supports making "transactions" involving a single file.
 * 
 * This necessitates certain architectural decisions.
 * One implication is that, when two objects are linked, you'll have to decide which gets uploaded first.
 * 
 * Let's look at a couple examples.
 * 
 * Example 1:
 *   You have a user object, and an associated avatar image (separate jpg file).
 *   So you upload the jpg file first, and then upload the user object file,
 *   which will reference the path to the jpg file on the server.
 *
 * Example 2:
 *   You have a new customer object, and an associated purchase object (which references the new customer).
 *   So you upload the customer object first, and the purchase second.
 *
 * In order to achieve this, you use the dependencies property, which is simply an array of path's.
 * That is, a reference to the operation.path that should go first.
 * 
 * For example 1 we might have:
 * - /users/robbie.json
 * - /avatars/robbie.jpg
 * 
 * And thus, since we want to upload the jpg first, we'd set:
 * userOperation.dependencies = @[ @"/avatars/robbie.jpg" ];
 * 
 * For example 2 we might have:
 * - /customers/abc123.json
 * - /purchases/xyz789.json
 * 
 * And thus, since we want to upload the customer first, we'd set:
 * purchaseOperation.dependencies = @[ @"/purchases/xyz789.json" ]
 *
 * It's important to understand some of the key concepts that dependencies enforce.
 * 
 * If there are two operations, 'A' & 'B', and B.dependencies=[A], then:
 *
 * - A is always started and completed before B is started.
 * - This applies regardless of the priority values for A & B.
 * - If a conflict is encountered for A, then B is still delayed until the conflict is resolved.
 *   This means that one of the following must occur:
 *   - A is properly merged with latest remote revision, and the operation is restarted & completed
 *   - A is skipped by marking it as complete (e.g. remote revision wins, local changes abandoned)
 *   - A is skipped by marking it as aborted, in which case B is automatically aborted
 * 
 * Also keep in mind that it's perfectly acceptable to add dependencies that may or may not exist as operations.
 * For example, if you always want to ensure that a customer is uploaded before his/her purchase,
 * then you can always set purchaseOrder.dependencies=["/customers/abc123.json"].
 * 
 * If the customer is created in the same transaction (and thus customer operation created),
 * then the graph system will automatically ensure the customer operations happens first.
 * And if the customer is not created in the same transaction (already existed, already on the server),
 * then the graph system simply ignores the dependency.
 * 
 * Note: Take care not to create circular dependencies.
 * If you do, the graph system will detect it, and throw an exception.
 * AKA - "If you create a circular dependency, you're gonna have a bad time."
 * 
 * @see addDependency
 * 
 * Mutability:
 *   Before the operation has been handed over to YapDatabaseCloudCore, this property is mutable.
 *   However, once the operation has been handed over to YapDatabaseCloudCore, it is marked as immutable,
 *   and you can no longer change this propery on the original operation instance.
 *   To make modifications, and properly persist them, you need to copy the operation instance,
 *   modify the copy, and then submit the copy to YapDatabaseCloudCore via 'modifyOperation:'.
 *
 *   For example:
 *   [databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
 *       YapDatabaseCloudCoreTransaction *cct = [transaction ext:@"MyCloud"];
 *       YapDatabaseCloudCoreOperation *modifiedOp = [[cct operationWithUUID:op.uuid inPipeline:op.pipeline] copy];
 *       [modifiedOp addDependency:x];
 *       [cct modifyOperation:operation];
 *   }];
**/
@property (nonatomic, copy, readwrite) NSSet *dependencies;

/**
 * Convenience method for adding a dependency to the list.
**/
- (void)addDependency:(id)dependency;

/**
 * Every operation can optionally be assigned a priority.
 * Operations with a higher priority will be prioritized over those with a lower priority.
 * 
 * There are several key concepts to keep in mind when it comes to prioritization.
 * 
 * 1. Dependencies trump priority, and are the perferred mechanism to enforce a required order.
 *    For example, if you need to upload 2 files (A & B), and B.dependencies=[A],
 *    then A will always start & complete before B is started, regardless of their priority values.
 * 
 * 2. Commit order is still enforced.
 *    Let's say you make commit #32 with operations A & B.
 *    Then you make commit #33 with operation C.
 *    Regardless of the priority of A, B & C, operations A & B will always complete before C is started.
 *    This is important to understand because it means you only have to concern yourself with the operations
 *    within a single commit. (Worrying about cross-commit dependencies & priorities quickly becomes overwhelming.)
 * 
 * 3. Operations may be executed in parallel.
 *    If commit #34 contains operations A & B, with no dependencies, and A.priority=2 & B.priority.1,
 *    then the pipeline will start operation A before starting operation B. However, since there are no
 *    dependencies, then the pipeline may start operation B before op A has completed.
 *    And thus, operation B may actually complete before operation A.
 *    For example, if A is a large record, but B is small record.
 * 
 * Thus it is best to think of dependencies as hard requirements, and priorities as soft hints.
 * 
 * Mutability:
 *   Before the operation has been handed over to YapDatabaseCloudCore, this property is mutable.
 *   However, once the operation has been handed over to YapDatabaseCloudCore, it is marked as immutable,
 *   and you can no longer change this propery on the original operation instance.
 *   To make modifications, and properly persist them, you need to copy the operation instance,
 *   modify the copy, and then submit the copy to YapDatabaseCloudCore via 'modifyOperation:'.
 *
 *   For example:
 *   [databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
 *       YapDatabaseCloudCoreTransaction *cct = [transaction ext:@"MyCloud"];
 *       YapDatabaseCloudCoreOperation *modifiedOp = [[cct operationWithUUID:op.uuid inPipeline:op.pipeline] copy];
 *       modifiedOp.priority = 100;
 *       [cct modifyOperation:operation];
 *   }];
**/
@property (nonatomic, assign, readwrite) int32_t priority;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark User Defined
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * User-defined information to associate with the operation.
 * This information is stored in the database along with the operation.
 *
 * Typical persistent info includes things such as:
 * - user information needed to perform the network operation (e.g. userID)
 * - information needed after the network operation completes (e.g. collection/key of associated database object)
 * 
 * @see setPersistentUserInfoObject:forKey:
 * 
 * Mutability:
 *   Before the operation has been handed over to YapDatabaseCloudCore, this property is mutable.
 *   However, once the operation has been handed over to YapDatabaseCloudCore, it is marked as immutable,
 *   and you can no longer change this propery on the original operation instance.
 *   To make modifications, and properly persist them, you need to copy the operation instance,
 *   modify the copy, and then submit the copy to YapDatabaseCloudCore via 'modifyOperation:'.
 * 
 *   For example:
 *   [databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
 *       YapDatabaseCloudCoreTransaction *cct = [transaction ext:@"MyCloud"];
 *       YapDatabaseCloudCoreOperation *modifiedOp = [[cct operationWithUUID:op.uuid inPipeline:op.pipeline] copy];
 *       [modifiedOp setPersistentUserInfoObject:obj forKey:key];
 *       [cct modifyOperation:operation];
 *   }];
**/
@property (nonatomic, copy, readwrite) NSDictionary *persistentUserInfo;

/**
 * Convenience method for modifying the persistentUserInfo dictionary.
**/
- (void)setPersistentUserInfoObject:(id)object forKey:(NSString *)key;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Equality
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Compares the receiver with the given operation.
**/
- (BOOL)isEqualToOperation:(YapDatabaseCloudCoreOperation *)operation;

@end
