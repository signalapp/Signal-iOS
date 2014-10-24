#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

#import "YapDatabaseTransaction.h"

@class YDBCKRecordInfo;

/**
 * Corresponds to the different type of blocks supported by the various extension subclasses.
**/
typedef NS_ENUM(NSInteger, YapDatabaseCloudKitBlockType) {
	YapDatabaseCloudKitBlockTypeWithKey       = 1,
	YapDatabaseCloudKitBlockTypeWithObject    = 2,
	YapDatabaseCloudKitBlockTypeWithMetadata  = 3,
	YapDatabaseCloudKitBlockTypeWithRow       = 4
};


@interface YapDatabaseCloudKitRecordHandler : NSObject

typedef id YapDatabaseCloudKitRecordBlock; // One of the YapDatabaseCloutKitGetRecordX types below.

/**
 * @param inOutRecordPtr
 * 
 * @param recordInfo
 * 
**/

typedef void (^YapDatabaseCloudKitRecordWithKeyBlock)
  (CKRecord **inOutRecordPtr, YDBCKRecordInfo *recordInfo, NSString *collection, NSString *key);
typedef void (^YapDatabaseCloudKitRecordWithObjectBlock)
  (CKRecord **inOutRecordPtr, YDBCKRecordInfo *recordInfo, NSString *collection, NSString *key, id object);
typedef void (^YapDatabaseCloudKitRecordWithMetadataBlock)
  (CKRecord **inOutRecordPtr, YDBCKRecordInfo *recordInfo, NSString *collection, NSString *key, id metadata);
typedef void (^YapDatabaseCloudKitRecordWithRowBlock)
  (CKRecord **inOutRecordPtr, YDBCKRecordInfo *recordInfo, NSString *collection, NSString *key, id object, id metadata);

+ (instancetype)withKeyBlock:(YapDatabaseCloudKitRecordWithKeyBlock)recordBlock;
+ (instancetype)withObjectBlock:(YapDatabaseCloudKitRecordWithObjectBlock)recordBlock;
+ (instancetype)withMetadataBlock:(YapDatabaseCloudKitRecordWithMetadataBlock)recordBlock;
+ (instancetype)withRowBlock:(YapDatabaseCloudKitRecordWithRowBlock)recordBlock;

@property (nonatomic, strong, readonly) YapDatabaseCloudKitRecordBlock recordBlock;
@property (nonatomic, assign, readonly) YapDatabaseCloudKitBlockType recordBlockType;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * "Clean" merge.
**/
typedef void (^YapDatabaseCloudKitMergeBlock)
       (YapDatabaseReadWriteTransaction *transaction, CKRecord *record, NSString *collection, NSString *key);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Conflict Block.
 * 
 * ...
**/
typedef void (^YapDatabaseCloudKitConflictBlock)
       (YapDatabaseReadWriteTransaction *transaction /* ??? */);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Database(ForIdentifier) Block.
 * 
 * CloudKit supports multiple databases.
 * There is the privateCloudDatabase & publicCloudDatabase of the defaultContainer.
 * In addition to this, apps may be configured with access to other (non-default) containers.
 * 
 * In order to properly support multiple databases, the DatabaseForIdentifier block is used.
 * Here's how it works:
 *
 * The recordHandler block is used to provide a CKRecord for a given row in the database.
 * In addition to the CKRecord, you may also specify a 'databaseIdentifier' via the YDBCKRecordInfo parameter.
 * If you specify a databaseIdentifier, then this method will be used in order to get an appropriate
 * CKDatabase instance for the databaseIdentifier you specified.
 * 
 * This block is OPTIONAL if you ONLY use [[CKContainer defaultContainer] privateCloudDatabase].
 *
 * That is, if you never specify a databaseIdentifier for any records (you leave databaseIdentifier nil),
 * then YapDatabaseCloudKit will assume & use [[CKContainer defaultContainer] privateCloudDatabase] for every CKRecord.
**/
typedef CKDatabase* (^YapDatabaseCloudKitDatabaseBlock)(NSString *databaseIdentifier);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YDBCKRecordInfo : NSObject

/**
 * This property allows you to specify the associated database for the record.
 * 
 * In order for YapDatabaseCloudKit to be able to upload the CKRecord to the cloud,
 * it must know which database the record is associated with.
 * 
 * If unspecified, the private database of the app’s default container is used.
 * 
 * Important:
 * If you specify a databaseIdentifier here,
 * you must also configure the YapDatabaseCloudKit instance with a Database(ForIdentifier) block.
**/
@property (nonatomic, copy, readwrite) NSString *databaseIdentifier;

/**
 * 
**/
@property (nonatomic, strong, readonly) NSArray *changedKeysToRestore;

@end
