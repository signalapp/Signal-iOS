#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseCloudKit.h"
#import "YapDatabaseCloudKitTypes.h"
#import "YapDatabaseCloudKitOptions.h"
#import "YapDatabaseCloudKitConnection.h"
#import "YapDatabaseCloudKitTransaction.h"

#import "YDBCKRecordInfo.h"
#import "YDBCKRecordTableInfo.h"
#import "YDBCKMappingTableInfo.h"
#import "YDBCKChangeQueue.h"
#import "YDBCKChangeRecord.h"

#import "YapDatabaseExtensionPrivate.h"
#import "YapCache.h"

#import "sqlite3.h"

/**
 * This version number is stored in the yap2 table.
 * If there is a major re-write to this class, then the version number will be incremented,
 * and the class can automatically rebuild the tables as needed.
**/
#define YAP_DATABASE_CLOUD_KIT_CLASS_VERSION 3

static NSString *const changeset_key_deletedRowids    = @"deletedRowids";    // Array: rowid
static NSString *const changeset_key_deletedHashes    = @"deletedHashes";    // Array: string
static NSString *const changeset_key_mappingTableInfo = @"mappingTableInfo"; // Dict : rowid -> CleanMappingTableInfo
static NSString *const changeset_key_recordTableInfo  = @"recordTableInfo";  // Dict : string -> CleanRecordTableInfo
static NSString *const changeset_key_reset            = @"reset";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCloudKitRecordHandler () {
@public
	
	YapDatabaseCloudKitRecordBlock block;
	YapDatabaseBlockType           blockType;
	YapDatabaseBlockInvoke         blockInvokeOptions;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YDBCKRecordInfo ()

@property (nonatomic, strong, readwrite) id versionInfo;
@property (nonatomic, strong, readwrite) NSArray *keysToRestore;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YDBCKMergeInfo ()

@property (nonatomic, strong, readwrite) CKRecord *pendingLocalRecord;
@property (nonatomic, strong, readwrite) CKRecord *updatedPendingLocalRecord;

- (void)mergeNewerRecord:(CKRecord *)newerRecord newerOriginalValues:(NSDictionary *)newerOriginalValues;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCloudKit () {
@public
	
	YapDatabaseCloudKitRecordHandler *recordHandler;
	
	YapDatabaseCloudKitMergeBlock mergeBlock;
	YapDatabaseCloudKitOperationErrorBlock opErrorBlock;
	YapDatabaseCloudKitDatabaseIdentifierBlock databaseIdentifierBlock;
	
	NSString *versionTag;
	id versionInfo;
	
	YapDatabaseCloudKitOptions *options;
	
	YDBCKChangeQueue *masterQueue;
}

- (NSString *)mappingTableName;
- (NSString *)recordTableName;
- (NSString *)queueTableName;

- (void)asyncMaybeDispatchNextOperation:(BOOL)forceNotification;

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
	
	YapCache<NSNumber *, id> *cleanMappingTableInfoCache; // rowid -> {[ NSString, NSNull ]}
	YapCache<NSString *, id> *cleanRecordTableInfoCache;  // hash  -> {[ YDBCKCleanRecordTableInfo, NSNull ]}
	
	NSMutableDictionary<NSNumber *, YDBCKDirtyMappingTableInfo *> *dirtyMappingTableInfoDict;
	NSMutableDictionary<NSString *, YDBCKDirtyRecordTableInfo *> *dirtyRecordTableInfoDict;
	
	YapCache<NSString *, NSArray *> *recordKeysCache;
	
	BOOL reset;
	BOOL isOperationCompletionTransaction;
	BOOL isOperationPartialCompletionTransaction;
	
	NSMutableDictionary *pendingAttachRequests;
	
	NSMutableSet *changeset_deletedRowids;
	NSMutableSet *changeset_deletedHashes;
	NSMutableDictionary *changeset_mappingTableInfo;
	NSMutableDictionary *changeset_recordTableInfo;
}

- (id)initWithParent:(YapDatabaseCloudKit *)inCloudKit databaseConnection:(YapDatabaseConnection *)inDbC;

- (void)postCommitCleanup;
- (void)postRollbackCleanup;

- (sqlite3_stmt *)mappingTable_insertStatement;
- (sqlite3_stmt *)mappingTable_updateForRowidStatement;
- (sqlite3_stmt *)mappingTable_getInfoForRowidStatement;
- (sqlite3_stmt *)mappingTable_enumerateForHashStatement;
- (sqlite3_stmt *)mappingTable_removeForRowidStatement;
- (sqlite3_stmt *)mappingTable_removeAllStatement;

- (sqlite3_stmt *)recordTable_insertStatement;
- (sqlite3_stmt *)recordTable_updateOwnerCountStatement;
- (sqlite3_stmt *)recordTable_updateMetadataStatement;
- (sqlite3_stmt *)recordTable_updateRecordStatement;
- (sqlite3_stmt *)recordTable_getInfoForHashStatement;
- (sqlite3_stmt *)recordTable_getOwnerCountForHashStatement;
- (sqlite3_stmt *)recordTable_getCountForHashStatement;
- (sqlite3_stmt *)recordTable_enumerateStatement;
- (sqlite3_stmt *)recordTable_removeForHashStatement;
- (sqlite3_stmt *)recordTable_removeAllStatement;

- (sqlite3_stmt *)queueTable_insertStatement;
- (sqlite3_stmt *)queueTable_updateDeletedRecordIDsStatement;
- (sqlite3_stmt *)queueTable_updateModifiedRecordsStatement;
- (sqlite3_stmt *)queueTable_updateBothStatement;
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
}

- (id)initWithParentConnection:(YapDatabaseCloudKitConnection *)parentConnection
		   databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

- (void)handlePartiallyCompletedOperationWithChangeSet:(YDBCKChangeSet *)changeSet
                                          savedRecords:(NSArray *)savedRecords
                                      deletedRecordIDs:(NSArray *)deletedRecordIDs;

- (void)handleCompletedOperationWithChangeSet:(YDBCKChangeSet *)changeSet
                                 savedRecords:(NSArray *)savedRecords
                             deletedRecordIDs:(NSArray *)deletedRecordIDs;

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
 * - deletedRecordIDs   : Array of CKRecordID's
 * - modifiedRecords    : Array of YDBCKChangeRecord's (storing either a CKRecord or just changedKeys array)
**/
@interface YDBCKChangeSet () {
@public
	
	NSMutableArray *deletedRecordIDs;
	
	NSMutableDictionary<CKRecordID *, YDBCKChangeRecord *> *modifiedRecords;
}

- (instancetype)initWithUUID:(NSString *)uuid
                        prev:(NSString *)prev
          databaseIdentifier:(NSString *)databaseIdentifier
            deletedRecordIDs:(NSData *)serializedRecordIDs
             modifiedRecords:(NSData *)serializedModifiedRecords;

- (instancetype)initWithDatabaseIdentifier:(NSString *)databaseIdentifier;

- (instancetype)emptyCopy;
- (instancetype)fullCopy;

// Inherited:
//
// @property (nonatomic, readonly) BOOL isInFlight;
//
// @property (nonatomic, readonly) NSString *databaseIdentifier;
//
// @property (nonatomic, readonly) NSArray *recordIDsToDelete; // Array of CKRecordID's for CKModifyRecordsOperation
// @property (nonatomic, readonly) NSArray *recordsToSave;     // Array of CKRecord's for CKModifyRecordsOperation

@property (nonatomic, readwrite) BOOL isInFlight;

@property (nonatomic, strong, readwrite) NSString *uuid;
@property (nonatomic, strong, readwrite) NSString *prev;

@property (nonatomic, readonly) NSArray *recordsToSave_noCopy;

@property (nonatomic, readwrite) BOOL hasChangesToDeletedRecordIDs;
@property (nonatomic, readwrite) BOOL hasChangesToModifiedRecords;

// Blob to go in 'deletedRecordIDs' column of database row.
- (NSData *)serializeDeletedRecordIDs;

// Blob to go in 'modifiedRecords' column of database row.
- (NSData *)serializeModifiedRecords;

- (void)enumerateMissingRecordsWithBlock:(CKRecord* (^)(CKRecordID *recordID, NSArray *changedKeys))block;

@end

