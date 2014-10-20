#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseCloudKit.h"
#import "YapDatabaseCloudKitTypes.h"
#import "YapDatabaseCloudKitOptions.h"
#import "YapDatabaseCloudKitConnection.h"
#import "YapDatabaseCloudKitTransaction.h"

#import "YDBCKChangeQueue.h"
#import "YDBCKDirtyRecordInfo.h"
#import "YDBCKCleanRecordInfo.h"

#import "YapDatabaseExtensionPrivate.h"
#import "YapCache.h"

#import "sqlite3.h"

/**
 * This version number is stored in the yap2 table.
 * If there is a major re-write to this class, then the version number will be incremented,
 * and the class can automatically rebuild the tables as needed.
**/
#define YAP_DATABASE_CLOUD_KIT_CLASS_VERSION 1

static NSString *const changeset_key_deletedRowids    = @"deletedRowids";    // Array: @(rowid)
static NSString *const changeset_key_modifiedRecords  = @"modifiedRecords";  // Dict : @(rowid) -> sanitized CKRecord
static NSString *const changeset_key_reset            = @"reset";


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCloudKit () {
@public
	
	YapDatabaseCloudKitRecordBlock recordBlock;
	YapDatabaseCloudKitBlockType recordBlockType;
	
	YapDatabaseCloudKitMergeBlock mergeBlock;
	YapDatabaseCloudKitConflictBlock conflictBlock;
	YapDatabaseCloudKitDatabaseBlock databaseBlock;
	
	NSString *versionTag;
	YapDatabaseCloudKitOptions *options;
	
	YDBCKChangeQueue *masterQueue;
	NSOperationQueue *masterOperationQueue;
	
	YapDatabaseConnection *completionDatabaseConnection;
}

- (NSString *)recordTableName;
- (NSString *)queueTableName;

- (void)handleFailedOperation:(YDBCKChangeSet *)changeSet withError:(NSError *)error;
- (void)handleCompletedOperation:(YDBCKChangeSet *)changeSet withSavedRecords:(NSArray *)savedRecords;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCloudKitConnection () {
@protected
	
	id sharedKeySetForInternalChangeset;
	
@public
	
	__strong YapDatabaseCloudKit *parent;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;
	
	YapCache *cleanRecordInfo;
	
	NSMutableDictionary *dirtyRecordInfo;
	BOOL reset;
	BOOL isUploadCompletionTransaction;
	
	YDBCKChangeQueue *pendingQueue;
	
	NSMutableSet *deletedRowids;
	NSMutableDictionary *modifiedRecords;
}

- (id)initWithParent:(YapDatabaseCloudKit *)inCloudKit databaseConnection:(YapDatabaseConnection *)inDbC;

- (void)postCommitCleanup;
- (void)postRollbackCleanup;

- (sqlite3_stmt *)recordTable_insertStatement;
- (sqlite3_stmt *)recordTable_updateForRowidStatement;
- (sqlite3_stmt *)recordTable_getRowidForRecordStatement;
- (sqlite3_stmt *)recordTable_getInfoForRowidStatement;
- (sqlite3_stmt *)recordTable_getInfoForAllStatement;
- (sqlite3_stmt *)recordTable_removeForRowidStatement;
- (sqlite3_stmt *)recordTable_removeAllStatement;

- (sqlite3_stmt *)queueTable_insertStatement;
- (sqlite3_stmt *)queueTable_updateStatement;
- (sqlite3_stmt *)queueTable_removeForUuidStatement;
- (sqlite3_stmt *)queueTable_removeAllStatement;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCloudKitTransaction () {
@protected

	__unsafe_unretained YapDatabaseCloudKitConnection *parentConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;
	
	NSMutableDictionary *databaseCache;
	
@public
	
	
}

- (id)initWithParentConnection:(YapDatabaseCloudKitConnection *)parentConnection
		   databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

- (void)removeQueueRowWithUUID:(NSString *)uuid;
- (void)updateRecord:(CKRecord *)record withDatabaseIdentifier:(NSString *)databaseIdentifier
                                                potentialRowid:(NSNumber *)rowidNumber;

@end
