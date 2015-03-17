#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

#import "YDBCKRecordInfo.h"
#import "YDBCKMergeInfo.h"
#import "YapDatabaseTransaction.h"


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
 * Merge Block.
**/
typedef void (^YapDatabaseCloudKitMergeBlock)
    (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key,
	 CKRecord *remoteRecord, YDBCKMergeInfo *mergeInfo);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * OperationError Block.
 * 
 * ...
**/
typedef void (^YapDatabaseCloudKitOperationErrorBlock)
       (NSString *databaseIdentifier, NSError *operationError);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * DatabaseIdentifier Block.
 * 
 * CloudKit supports multiple databases.
 * There is the privateCloudDatabase & publicCloudDatabase of the defaultContainer.
 * In addition to this, apps may be configured with access to other (non-default) containers.
 * 
 * In order to properly support multiple databases, the DatabaseIdentifier block is used.
 * Here's how it works:
 *
 * The recordHandler block is used to provide a CKRecord for a given row in the database.
 * In addition to the CKRecord, you may also specify a 'databaseIdentifier' via the YDBCKRecordInfo parameter.
 * If you specify a databaseIdentifier, then this method will be used in order to get an appropriate
 * CKDatabase instance for the databaseIdentifier you specified.
 * 
 * If you ONLY use  [[CKContainer defaultContainer] privateCloudDatabase],
 * then you do NOT need to specify a DatabaseIdentifierBlock.
 *
 * That is, if you never specify a databaseIdentifier for any records (you leave recordInfo.databaseIdentifier nil),
 * then YapDatabaseCloudKit will assume & use [[CKContainer defaultContainer] privateCloudDatabase] for every CKRecord.
 * 
 * However, if you intend to use any other CKDatabase, the you MUST provide a DatabaseIdentifierBlock.
**/
typedef CKDatabase* (^YapDatabaseCloudKitDatabaseIdentifierBlock)(NSString *databaseIdentifier);
