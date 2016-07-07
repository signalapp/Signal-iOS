/**
 * Copyright Deusty LLC.
**/

#import "YapDatabaseCloudCoreOperation.h"
#import "YapDatabaseCloudCoreFileOperation.h"
#import "YapDatabaseCloudCoreRecordOperation.h"

#import "YapDatabaseCloudCoreOptions.h"
#import "YapDatabaseCloudCorePipeline.h"

@class YapDatabaseCloudCore;


NS_INLINE BOOL YDB_IsEqualOrBothNil(id obj1, id obj2)
{
	if (obj1)
		return [obj1 isEqual:obj2];
	else
		return (obj2 == nil);
}

@interface YapDatabaseCloudCoreOperation () {
@protected
	
	NSMutableSet *changedProperties;
}

#pragma mark Internal Properties

/**
 * Represents the operation's rowid (primary key) in the queue table (that stores all operations).
 * This property is set automatically once the operation has been written to disk.
 *
 * This property does NOT need to be included during serialization.
 * It gets it own separate column in the database table (obviously).
**/
@property (nonatomic, assign, readwrite) int64_t operationRowid;


#pragma mark Import

/**
 * An operation can be imported once, and only once.
 * This thread-safe method will only return YES the very first time it's called.
 * This helps ensure the same operation instance isn't mistakenly submitted multiple times.
 * 
 * Subclasses may optionally override this method to do something with the options parameter.
 * Subclasses must invoke [super import:], and pay attention to the return value.
**/
- (BOOL)import:(YapDatabaseCloudCoreOptions *)options;

/**
 * Returns YES once the operation has been imported.
**/
@property (atomic, readonly) BOOL isImported;


#pragma mark Transactional Changes

/**
 * Set 'needsDeleteDatabaseRow' (within a read-write transaction) to have the operation deleted from the database.
 * Set 'needsModifyDatabaseRow' (within a read-write transaction) to have the operation rewritten to the database.
 * 
 * As one would expect, 'needsDeleteDatabaseRow' trumps 'needsModifyDatabaseRow'.
 * So if both are set, the operation will be deleted from the database.
**/
@property (nonatomic, assign, readwrite) BOOL needsDeleteDatabaseRow;
@property (nonatomic, assign, readwrite) BOOL needsModifyDatabaseRow;

/**
 * The status that will get synced to the pipeline after the transaction is committed.
**/
@property (nonatomic, strong, readwrite) NSNumber *pendingStatus;

@property (nonatomic, readonly) BOOL pendingStatusIsCompletedOrSkipped;
@property (nonatomic, readonly) BOOL pendingStatusIsCompleted;
@property (nonatomic, readonly) BOOL pendingStatusIsSkipped;

- (void)clearTransactionVariables;

#pragma mark Subclass API

/**
 * Subclasses MUST override this method.
 *
 * Represents the cloudURI to use if attaching the collection/key tuple.
 *
 * This property is abstract, and must be overriden by subclasses to return a value.
 * This property is optional.
 * If a non-nil value is returned, the cloudURI will be attached to the collection/key tuple.
 * If a nil value is returned, no attaching will occur.
**/
- (NSString *)attachCloudURI;

/**
 * Subclasses MUST override this method.
 * 
 * The dependencyUUIDs must generated for each operation prior to handing it to the pipeline/graph.
 * This is typically done in [YapDatabaseCloudCoreTransaction processOperations:::].
**/
- (NSSet *)dependencyUUIDs;

/**
 * Subclasses may optionally override this method.
 *
 * This method is used to enforce which type of dependencies are valid.
 * For example, the following classes may be allowed depending on the domain:
 *  - uuid
 *  - string
 *  - url
 *  - CKRecordID
 * 
 * The answer is rather domain dependent, and thus this override provide the opportunity to enforce policy.
**/
- (BOOL)validateDependencies:(NSArray *)dependencies;

#pragma mark Immutability

/**
 * Subclasses should override and add properties that shouldn't be changed after
 * the operation has been marked immutable.
**/
+ (NSMutableSet *)monitoredProperties;

@property (nonatomic, readonly) BOOL isImmutable;
- (void)makeImmutable;

@property (nonatomic, readonly) BOOL hasChanges;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

typedef NS_ENUM(NSInteger, YDBCloudFileOpProcessResult) {
	
	YDBCloudFileOpProcessResult_Continue,
	YDBCloudFileOpProcessResult_MergedIntoLater,
	YDBCloudFileOpProcessResult_DependentOnEarlier,
	YDBCloudFileOpProcessResult_DependentOnLater,
};

@interface YapDatabaseCloudCoreFileOperation () {
@protected
	
	BOOL implicitAttach;
}

/**
 * The 'type' & 'cloudPath' may NOT be nil.
**/
- (instancetype)initWithType:(NSString *)type
                   cloudPath:(YapFilePath *)cloudPath
             targetCloudPath:(YapFilePath *)targetCloudPath;

- (void)clearDependencyUUIDs;
- (void)addDependencyUUID:(NSUUID *)uuid;
- (void)replaceDependencyUUID:(NSUUID *)oldUUID with:(NSUUID *)newUUID;

- (YDBCloudFileOpProcessResult)processEarlierOperationFromSameTransaction:(YapDatabaseCloudCoreFileOperation *)earlierOp;
- (void)mergeEarlierOperationFromSameTransaction:(YapDatabaseCloudCoreFileOperation *)earlierOp;

- (instancetype)updateWithOperationFromLaterTransaction:(YapDatabaseCloudCoreFileOperation *)newOperation;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCloudCoreRecordOperation ()

/**
 * Temporary variable used during extension registartion.
 * Only used to set YDBCloudCoreRestoreInfo.changedKeys property.
**/
@property (nonatomic, strong, readwrite) NSArray *restoreInfo_changedKeys;

/**
 * If YES, then the updatedValues dictionary needs to be persisted to disk (during operation serialization).
 * If NO, then only updatedValues.allKeys needs to be persisted to disk,
 * and the values themselves can be restored via YapDatabaseCloudCoreHandler + YDBCloudCoreRestoreInfo.changedKeys.
**/
@property (nonatomic, assign, readwrite) BOOL needsStoreFullUpdatedValues;

@end
