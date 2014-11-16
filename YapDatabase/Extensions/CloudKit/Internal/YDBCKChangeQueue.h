#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

@class YDBCKChangeSet;


@interface YDBCKChangeQueue : NSObject

/**
 * Every YapDatabaseCloudKit instance has a single masterQueue,
 * which tracks the CloutKit related changeSets per commit.
 * 
 * This information is used to create and track the NSOperation's that are pushing data to the cloud,
 * as well as the corresponding information that we need to save to persistent storage.
**/
- (instancetype)initMasterQueue;

#pragma mark Lifecycle

/**
 * This method is used during extension registration
 * after the old changeSets, from previous app run(s), have been restored.
 * 
 * This method MUST be called from within the readWriteTransaction that registers the extension.
**/
- (void)restoreOldChangeSets:(NSArray *)oldChangeSets;

/**
 * If there is NOT already an in-flight changeSet, then this method sets the appropriate flag(s),
 * and returns the next changeSet ready for upload.
**/
- (YDBCKChangeSet *)makeInFlightChangeSet;

/**
 * If there is an in-flight changeSet,
 * then this method removes it to make room for new in-flight changeSets.
**/
- (void)removeCompletedInFlightChangeSet;

/**
 * If there is an in-flight changeSet,
 * then this method "resets" it so it can be restarted again (when ready).
**/
- (void)resetFailedInFlightChangeSet;

/**
 * Invoke this method from 'prepareForReadWriteTransaction' in order to fetch a 'pendingQueue' object.
 *
 * This pendingQueue object will then be used to keep track of all the changes
 * that need to be written to the changesTable.
 *
 * This method MUST be called from within a readWriteTransaction.
 *
 * Keep in mind that the creation of a pendingQueue locks the masterQueue until
 * that pendingQueue is merged via mergePendingQueue.
**/
- (YDBCKChangeQueue *)newPendingQueue;

/**
 * This should be done AFTER the pendingQueue has been written to disk,
 * at the end of the flushPendingChangesToExtensionTables method.
 * 
 * This method MUST be called from within a readWriteTransaction.
 * 
 * Keep in mind that the creation of a pendingQueue locks the masterQueue until
 * that pendingQueue is merged via mergePendingQueue.
**/
- (void)mergePendingQueue:(YDBCKChangeQueue *)pendingQueue;

#pragma mark Properties

/**
 * Determining queue type.
 * Primarily used for sanity checks.
**/
@property (nonatomic, readonly) BOOL isMasterQueue;
@property (nonatomic, readonly) BOOL isPendingQueue;

/**
 * Each commit that makes one or more changes to a CKRecord (insert/modify/delete)
 * will result in one or more YDBCKChangeSet(s).
 * There is one YDBCKChangeSet per databaseIdentifier.
 * So a single commit may possibly generate multiple changeSets.
 *
 * Thus a changeSet encompasses all the relavent CloudKit related changes per database, per commit.
**/
@property (nonatomic, strong, readonly) NSArray *changeSetsFromPreviousCommits;
@property (nonatomic, strong, readonly) NSArray *changeSetsFromCurrentCommit;

#pragma mark Merge Handling

/**
 * This method enumerates pendingChangeSetsFromPreviousCommits, from oldest commit to newest commit,
 * and merges the changedKeys & values into the given record.
 * Thus, if the value for a particular key has been changed multiple times,
 * then the given record will end up with the most recent value for that key.
 * 
 * The given record is expected to be a sanitized record.
 * 
 * Returns YES if there were any pending records in the pendingChangeSetsFromPreviousCommits.
**/
- (BOOL)mergeChangesForRowid:(NSNumber *)rowidNumber intoRecord:(CKRecord *)record;

#pragma mark Transaction Handling

/**
 * This method:
 * - creates a changeSet for the given databaseIdentifier for the current commit (if needed)
 * - adds the record to the changeSet
 * 
 * The following may be modified:
 * - pendingQueue.changeSetsFromCurrentCommit
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
         withInsertedRowid:(NSNumber *)rowidNumber
                    record:(CKRecord *)record
        databaseIdentifier:(NSString *)databaseIdentifier;

/**
 * This method:
 * - creates a changeSet for the given databaseIdentifier for the current commit (if needed)
 * - adds the record to the changeSet
 * - modifies the changeSets from previous commits that also modified the same rowid (if needed)
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
 * - pendingQueue.changeSetsFromCurrentCommit
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
         withModifiedRowid:(NSNumber *)rowidNumber
                    record:(CKRecord *)record
        databaseIdentifier:(NSString *)databaseIdentifier;

/**
 * This method:
 * - modifies the changeSets from previous commits that also modified the same rowid (if needed)
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
         withDetachedRowid:(NSNumber *)rowidNumber;

/**
 * This method:
 * - creates a changeSet for the given databaseIdentifier for the current commit (if needed)
 * - adds the deleted recordID to the changeSet
 * - modifies the changeSets from previous commits that also modified the same rowid (if needed)
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
 * - pendingQueue.changeSetsFromCurrentCommit
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
          withDeletedRowid:(NSNumber *)rowidNumber
                  recordID:(CKRecordID *)ckRecordID
        databaseIdentifier:(NSString *)databaseIdentifier;

/**
 * This method:
 * - modifies the changeSets from previous commits that also modified the same rowid (if needed),
 *   if the mergedRecord disagrees with the pending record.
 * - If the mergedRecord contains values that aren're represending in previous commits,
 *   then it creates a changeSet for the given databaseIdentifier for the current commit,
 *   and adds a record with the missing values.
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
 * - pendingQueue.changeSetsFromCurrentCommit
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
           withMergedRowid:(NSNumber *)rowidNumber
                    record:(CKRecord *)mergedRecord
        databaseIdentifier:(NSString *)databaseIdentifier;

/**
 * This method:
 * - modifies the changeSets from previous commits that also modified the same rowid (if needed)
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
    withRemoteDeletedRowid:(NSNumber *)rowidNumber
                  recordID:(CKRecordID *)recordID
        databaseIdentifier:(NSString *)databaseIdentifier;

/**
 *
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
            withSavedRowid:(NSNumber *)rowidNumber
                    record:(CKRecord *)record
        databaseIdentifier:(NSString *)databaseIdentifier
     isOpPartialCompletion:(BOOL)isOpPartialCompletion;

/**
 * This method:
 * - modifies the inFlightChangeSet by removing the given recordID from the deletedRecordIDs
 * 
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
     withSavedDeletedRowid:(NSNumber *)rowidNumber
                  recordID:(CKRecordID *)recordID
        databaseIdentifier:(NSString *)databaseIdentifier;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This class represents a row in the queue table.
 * Every row contains the following columns:
 * 
 * - uuid : The unique primary key
 * - prev : The previous row, representing the commit prior to this one (reverse linked-list style)
 *
 * - databaseIdentifier : The databaseIdentifier for all deleted CKRecordIDs & modified CKRecords
 * 
 * - deletedRecordIDs   : A blob of the CKRecordIDs that are to be marked as deleted.
 * - modifiedRecords    : A blob represending the rowid & modified info (either CKRecord or just changedKeys array).
**/
@interface YDBCKChangeSet : NSObject

- (id)initWithUUID:(NSString *)uuid
              prev:(NSString *)prev
databaseIdentifier:(NSString *)databaseIdentifier
  deletedRecordIDs:(NSData *)serializedRecordIDs
   modifiedRecords:(NSData *)serializedModifiedRecords;

@property (nonatomic, strong, readonly) NSString *uuid;
@property (nonatomic, strong, readonly) NSString *prev;

@property (nonatomic, strong, readonly) NSString *databaseIdentifier;

@property (nonatomic, readonly) NSArray *recordIDsToDelete; // Array of CKRecordID's for CKModifyRecordsOperation
@property (nonatomic, readonly) NSArray *recordsToSave;     // Array of CKRecord's for CKModifyRecordsOperation

@property (nonatomic, readonly) BOOL hasChangesToDeletedRecordIDs;
@property (nonatomic, readonly) BOOL hasChangesToModifiedRecords;

- (NSData *)serializeDeletedRecordIDs; // Blob to go in 'deletedRecordIDs' column of database row
- (NSData *)serializeModifiedRecords;  // Blob to go in 'modifiedRecords' column of database row

- (void)enumerateMissingRecordsWithBlock:(CKRecord* (^)(int64_t rowid, NSArray *changedKeys))block;

- (NSDictionary *)recordIDToRowidMapping;

@end
