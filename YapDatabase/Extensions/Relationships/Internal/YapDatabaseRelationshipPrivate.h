#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseRelationship.h"
#import "YapDatabaseRelationshipOptions.h"
#import "YapDatabaseRelationshipConnection.h"
#import "YapDatabaseRelationshipTransaction.h"

#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"

#import "YapCache.h"

/**
 * This version number is stored in the yap2 table.
 * If there is a major re-write to this class, then the version number will be incremented,
 * and the class can automatically rebuild the table as needed.
**/
#define YAP_DATABASE_RELATIONSHIP_CLASS_VERSION 4

/**
 * Keys for yap2 extension configuration table.
**/

static NSString *const ext_key_classVersion       = @"classVersion";
static NSString *const ext_key_versionTag         = @"versionTag";
static NSString *const ext_key_version_deprecated = @"version";

/**
 * Keys for changeset dictionary.
**/

static NSString *const changeset_key_deletedEdges  = @"deletedEdges";
static NSString *const changeset_key_modifiedEdges = @"modifiedEdges";
static NSString *const changeset_key_reset         = @"reset";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRelationship () {
@public

	NSString *versionTag;
	YapDatabaseRelationshipOptions *options;
}

- (NSString *)tableName;

/**
 * The dispatch queue for performing file deletion operations.
 * Note: This method is not thread-safe, as it expects to only be invoked from within a read-write transaction.
**/
- (dispatch_queue_t)fileManagerQueue;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRelationshipOptions () {
@public
	
	BOOL disableYapDatabaseRelationshipNodeProtocol;
	YapWhitelistBlacklist *allowedCollections;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRelationshipConnection () {
@protected
	
	id sharedKeySetForInternalChangeset;
	
@public
	
	__strong YapDatabaseRelationship *parent;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;
	
	YapCache<NSNumber*, YapDatabaseRelationshipEdge*> *edgeCache;                // key:edgeRowid, value:edge
	
	NSMutableDictionary<NSNumber*, NSMutableArray*> *protocolChanges;            // key:srcRowid, value:edges
	NSMutableDictionary<NSString*, NSMutableArray*> *manualChanges;              // key:edgeName, value:edges
	
	NSMutableSet<NSNumber*> *inserted;                                           // values:db_rowid
	
	NSMutableArray<NSNumber*> *deletedOrder;                                     // values:db_rowid
	NSMutableDictionary<NSNumber*, YapCollectionKey*> *deletedInfo;              // key:db_rowid, value:collectionKey
	
	BOOL reset;
	
	NSMutableSet<NSNumber *> *deletedEdges;                                      // values:edgeRowid
	NSMutableDictionary<NSNumber*, YapDatabaseRelationshipEdge*> *modifiedEdges; // key:edgeRowid, value:edge
	
	NSMutableSet<NSURL *> *filesToDelete;
}

- (id)initWithParent:(YapDatabaseRelationship *)parent databaseConnection:(YapDatabaseConnection *)databaseConnection;

- (void)postCommitCleanup;
- (void)postRollbackCleanup;

- (sqlite3_stmt *)findEdgesWithNodeStatement;
- (sqlite3_stmt *)findManualEdgeWithDstStatement;
- (sqlite3_stmt *)findManualEdgeWithDstFileURLStatement;
- (sqlite3_stmt *)insertEdgeStatement;
- (sqlite3_stmt *)updateEdgeStatement;
- (sqlite3_stmt *)deleteEdgeStatement;
- (sqlite3_stmt *)deleteEdgesWithNodeStatement;
- (sqlite3_stmt *)enumerateDstFileURLWithSrcStatement:(BOOL *)needsFinalizePtr;
- (sqlite3_stmt *)enumerateDstFileURLWithSrcNameStatement:(BOOL *)needsFinalizePtr;
- (sqlite3_stmt *)enumerateDstFileURLWithNameStatement:(BOOL *)needsFinalizePtr;
- (sqlite3_stmt *)enumerateDstFileURLWithNameExcludingSrcStatement:(BOOL *)needsFinalizePtr;
- (sqlite3_stmt *)enumerateAllDstFileURLStatement:(BOOL *)needsFinalizePtr;
- (sqlite3_stmt *)enumerateForSrcStatement:(BOOL *)needsFinalizePtr;
- (sqlite3_stmt *)enumerateForDstStatement:(BOOL *)needsFinalizePtr;
- (sqlite3_stmt *)enumerateForSrcNameStatement:(BOOL *)needsFinalizePtr;
- (sqlite3_stmt *)enumerateForDstNameStatement:(BOOL *)needsFinalizePtr;
- (sqlite3_stmt *)enumerateForNameStatement:(BOOL *)needsFinalizePtr;
- (sqlite3_stmt *)enumerateForSrcDstStatement:(BOOL *)needsFinalizePtr;
- (sqlite3_stmt *)enumerateForSrcDstNameStatement:(BOOL *)needsFinalizePtr;
- (sqlite3_stmt *)countForSrcNameExcludingDstStatement;
- (sqlite3_stmt *)countForDstNameExcludingSrcStatement;
- (sqlite3_stmt *)countForNameStatement;
- (sqlite3_stmt *)countForSrcStatement;
- (sqlite3_stmt *)countForSrcNameStatement;
- (sqlite3_stmt *)countForDstStatement;
- (sqlite3_stmt *)countForDstNameStatement;
- (sqlite3_stmt *)countForSrcDstStatement;
- (sqlite3_stmt *)countForSrcDstNameStatement;
- (sqlite3_stmt *)removeAllStatement;
- (sqlite3_stmt *)removeAllProtocolStatement;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRelationshipTransaction () {
@protected
	
	__unsafe_unretained YapDatabaseRelationshipConnection *parentConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;
}

- (id)initWithParentConnection:(YapDatabaseRelationshipConnection *)parentConnection
           databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

@end
