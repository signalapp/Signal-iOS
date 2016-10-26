/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>


/**
 * This is the base class for concrete subclasses such as FileOperations & RecordOperations.
 *
 * Do not directly create instances of this class.
 * Instead create instances of concrete subclass.
**/
@interface YapDatabaseCloudCoreOperation : NSObject <NSCoding, NSCopying>

/**
 * Every operation has a randomly generated UUID.
 * This is used for dependency references, and for uniquely identifying this specific operation.
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
**/
@property (nonatomic, copy, readwrite) NSString *pipeline;

/**
 * At the local level, when dealing with YapDatabase, you have the benefit of atomic transactions.
 * Thus you can make changes to multiple objects, and apply the changes in an atomic fashion.
 * However, the cloud server may only support "transactions" involving a single file.
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
 * In order to achieve this, you use the dependencies property, which is simply an array of UUID's.
 * That is, a reference to any operation.uuid that must go first.
 * 
 * For example 1 we might have:
 * - opA : /users/robbie.json
 * - opB : /avatars/robbie.jpg
 * 
 * And thus, since we want to upload the jpg first, we'd set:
 * opA.dependencies = @[ opB.uuid ];
 * 
 * For example 2 we might have:
 * - opA : /customers/abc123.json
 * - opB : /purchases/xyz789.json
 * 
 * And thus, since we want to upload the customer first, we'd set:
 * opB.dependencies = @[ opA.uuid ]
 *
 * It's important to understand some of the key concepts that dependencies enforce.
 * 
 * If there are two operations, 'A' & 'B', and B.dependencies=[A.uuid], then:
 *
 * - A is always started and completed before B is started.
 * - This applies regardless of the priority values for A & B.
 * - If a conflict is encountered for A, then B is still delayed until the conflict is resolved.
 *   This means that one of the following must occur:
 *   - A is marked as completed
 *   - A is marked as skipped
 * 
 * If you create a circular dependency, the graph system will detect it and throw an exception.
 * 
 * @see addDependency
**/
@property (nonatomic, copy, readwrite) NSSet<NSUUID *> *dependencies;

/**
 * Convenience method for adding a dependency to the list.
 *
 * @param op - May be either a NSUUID, or a YapDatabaseCloudCoreOperation (for convenience).
**/
- (void)addDependency:(id)op;

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
