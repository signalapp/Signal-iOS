#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

#import "YDBCKChangeSet.h"
#import "YDBCKMergeInfo.h"


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
- (YDBCKChangeSet *)makeInFlightChangeSet:(BOOL *)isAlreadyInFlightPtr;

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

#pragma mark Change-Sets Access

/**
 * Returns the changeSet.uuid of the "current" changeSet,
 * which is either the inFlightChangeSet, or the next changeSet to go inFlight once resumed.
 *
 * In other words, the first YDBCKChangeSet in the queue.
**/
- (NSString *)currentChangeSetUUID;

/**
 * Returns the "current" changeSet,
 * which is either the inFlightChangeSet, or the next changeSet to go inFlight once resumed.
 * 
 * In other words, the first YDBCKChangeSet in the queue.
**/
- (YDBCKChangeSet *)currentChangeSet;

/**
 * Each commit that makes one or more changes to a CKRecord (insert/modify/delete)
 * will result in one or more YDBCKChangeSet(s).
 * There is one YDBCKChangeSet per databaseIdentifier.
 * So a single commit may possibly generate multiple changeSets.
 *
 * Thus a changeSet encompasses all the relavent CloudKit related changes per database, per commit.
**/
- (NSArray *)changeSetsFromPreviousCommits;
- (NSArray *)changeSetsFromCurrentCommit;

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
 * numberOfInFlightChangeSets == numberOfPendingChangeSets - numberOfQueuedChangeSets
 * numberOfQueuedChangeSets   == numberOfPendingChangeSets - numberOfInFlightChangeSets
 * numberOfPendingChangeSets  == numberOfPendingChangeSets + numberOfQueuedChangeSets
**/
@property (atomic, readonly) NSUInteger numberOfInFlightChangeSets;
@property (atomic, readonly) NSUInteger numberOfQueuedChangeSets;
@property (atomic, readonly) NSUInteger numberOfPendingChangeSets;

/**
 * Atomic access to all counts at once.
**/
- (void)getNumberOfInFlightChangeSets:(NSUInteger *)numInFlightChangeSetsPtr
                     queuedChangeSets:(NSUInteger *)numQueuedChangeSetsPtr;

#pragma mark Merge Handling

/**
 * Check in pendingChangeSetsFromPreviousCommits to see what kind of changes are pending.
**/
- (void)getHasPendingModification:(BOOL *)outHasPendingModification
                 hasPendingDelete:(BOOL *)outHasPendingDelete
                      forRecordID:(CKRecordID *)recordID
               databaseIdentifier:(NSString *)databaseIdentifier;

/**
 * This method enumerates pendingChangeSetsFromPreviousCommits, from oldest commit to newest commit,
 * and merges the changedKeys & values into the given record.
 * Thus, if the value for a particular key has been changed multiple times,
 * then the given record will end up with the most recent value for that key.
 * 
 * The given record is expected to be a sanitized record.
 * 
 * Returns YES if there are any pending records in the pendingChangeSetsFromPreviousCommits.
**/
- (BOOL)mergeChangesForRecordID:(CKRecordID *)recordID
             databaseIdentifier:(NSString *)databaseIdentifier
                           into:(YDBCKMergeInfo *)mergeInfo;

#pragma mark Transaction Commit Handling

/**
 * This method:
 * - creates a changeSet for the given databaseIdentifier for the current commit (if needed)
 * - adds the record to the changeSet
 * 
 * The following may be modified:
 * - pendingQueue.changeSetsFromCurrentCommit
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
        withInsertedRecord:(CKRecord *)record
        databaseIdentifier:(NSString *)databaseIdentifier;

/**
 * This method:
 * - creates a changeSet for the given databaseIdentifier for the current commit (if needed)
 * - adds the record to the changeSet
 * - modifies the changeSets from previous commits that also modified the same record (if needed)
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
 * - pendingQueue.changeSetsFromCurrentCommit
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
        withModifiedRecord:(CKRecord *)record
        databaseIdentifier:(NSString *)databaseIdentifier
            originalValues:(NSDictionary *)originalValues;

/**
 * This method:
 * - modifies the changeSets from previous commits that also modified the same record (if needed)
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
      withDetachedRecordID:(CKRecordID *)recordID
        databaseIdentifier:(NSString *)databaseIdentifier;

/**
 * This method:
 * - creates a changeSet for the given databaseIdentifier for the current commit (if needed)
 * - adds the deleted recordID to the changeSet
 * - modifies the changeSets from previous commits that also modified the same record (if needed)
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
 * - pendingQueue.changeSetsFromCurrentCommit
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
       withDeletedRecordID:(CKRecordID *)recordID
        databaseIdentifier:(NSString *)databaseIdentifier;

/**
 * This method:
 * - modifies the changeSets from previous commits that also modified the same record (if needed),
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
          withMergedRecord:(CKRecord *)mergedRecord
        databaseIdentifier:(NSString *)databaseIdentifier;

/**
 * This method:
 * - modifies the changeSets from previous commits that also modified the same record (if needed)
 *
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
 withRemoteDeletedRecordID:(CKRecordID *)recordID
        databaseIdentifier:(NSString *)databaseIdentifier;

/**
 * This method
 * - removes the record from the inFlightChangeSet (if isOpPartialCompletion)
 * - if modifications for the same record are queued in other changeSets, then updates the base record (system metadata)
 *   for those records (such that the have the latest recordChangeTag, etc)
 * 
 * The following may be modified:
 * - pendingQueue.changeSetsFromPreviousCommits
**/
- (void)updatePendingQueue:(YDBCKChangeQueue *)pendingQueue
           withSavedRecord:(CKRecord *)record
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
  withSavedDeletedRecordID:(CKRecordID *)recordID
        databaseIdentifier:(NSString *)databaseIdentifier;

@end
