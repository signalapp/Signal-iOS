#import <Foundation/Foundation.h>
#import <CloudKit/CloudKit.h>

#import "YapDatabaseExtensionTypes.h"
#import "YDBCKRecordInfo.h"
#import "YDBCKMergeInfo.h"

@class YapDatabaseReadTransaction;
@class YapDatabaseReadWriteTransaction;

NS_ASSUME_NONNULL_BEGIN

/**
 * The RecordHandler is the primary mechanism that is used to tell YapDatabaseCloudKit about CKRecord changes.
 * That is, as you make changes to your own custom data model objects, you can use the RecordHandler block to tell
 * YapDatabaseCloudKit about the changes that were made by handing it CKRecords.
 * 
 * Here's the general idea:
 * - You update an object in the database via the normal setObject:forKey:inCollection method.
 * - Since YapDatabaseCloudKit is an extension, it's automatically notified that you modified an object.
 * - YapDatabaseCloudKit then invokes the recordHandler, and passes you the modified object,
 *   along with an empty base CKRecord (if available), and asks you to set the proper values on the record.
 * - Afterwards, the extension will check to see if it needs to upload the CKRecord (if it has changes),
 *   and handles the rest if it does.
 * 
 * For more information & sample code, please see the wiki:
 * https://github.com/yapstudios/YapDatabase/wiki/YapDatabaseCloudKit#RecordHandlerBlock
**/
@interface YapDatabaseCloudKitRecordHandler : NSObject

typedef id YapDatabaseCloudKitRecordBlock; // One of the YapDatabaseCloutKitGetRecordX types below.

typedef void (^YapDatabaseCloudKitRecordWithKeyBlock)
    (YapDatabaseReadTransaction *transaction, CKRecord *_Nonnull *_Nullable inOutRecordPtr, YDBCKRecordInfo *recordInfo,
     NSString *collection, NSString *key);

typedef void (^YapDatabaseCloudKitRecordWithObjectBlock)
    (YapDatabaseReadTransaction *transaction, CKRecord *_Nonnull *_Nullable inOutRecordPtr, YDBCKRecordInfo *recordInfo,
     NSString *collection, NSString *key, id object);

typedef void (^YapDatabaseCloudKitRecordWithMetadataBlock)
    (YapDatabaseReadTransaction *transaction, CKRecord *_Nonnull *_Nullable inOutRecordPtr, YDBCKRecordInfo *recordInfo,
     NSString *collection, NSString *key, __nullable id metadata);

typedef void (^YapDatabaseCloudKitRecordWithRowBlock)
    (YapDatabaseReadTransaction *transaction, CKRecord *_Nonnull *_Nullable inOutRecordPtr, YDBCKRecordInfo *recordInfo,
     NSString *collection, NSString *key, id object, __nullable id metadata);

+ (instancetype)withKeyBlock:(YapDatabaseCloudKitRecordWithKeyBlock)recordBlock;
+ (instancetype)withObjectBlock:(YapDatabaseCloudKitRecordWithObjectBlock)recordBlock;
+ (instancetype)withMetadataBlock:(YapDatabaseCloudKitRecordWithMetadataBlock)recordBlock;
+ (instancetype)withRowBlock:(YapDatabaseCloudKitRecordWithRowBlock)recordBlock;

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops keyBlock:(YapDatabaseCloudKitRecordWithKeyBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops objectBlock:(YapDatabaseCloudKitRecordWithObjectBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops metadataBlock:(YapDatabaseCloudKitRecordWithMetadataBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops rowBlock:(YapDatabaseCloudKitRecordWithRowBlock)block;

@property (nonatomic, strong, readonly) YapDatabaseCloudKitRecordBlock block;
@property (nonatomic, assign, readonly) YapDatabaseBlockType           blockType;
@property (nonatomic, assign, readonly) YapDatabaseBlockInvoke         blockInvokeOptions;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The MergeBlock is used to merge a CKRecord, which may come from a different device or different user,
 * into the local system.
 * 
 * The MergeBlock is used to perform two tasks:
 * - It allows you to merge changes (generally made on a different machine) into your local data model object.
 * - It allows you to modify YapDatabaseCloudKit's change-set queue in the event there are any conflicts.
 * 
 * For more information & sample code, please see the wiki:
 * https://github.com/yapstudios/YapDatabase/wiki/YapDatabaseCloudKit#MergeBlock
**/
typedef void (^YapDatabaseCloudKitMergeBlock)
    (YapDatabaseReadWriteTransaction *transaction, NSString * _Nullable collection, NSString * _Nullable key,
	 CKRecord *remoteRecord, YDBCKMergeInfo *mergeInfo);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * When YapDatabaseCloudKit goes to push a change-set to the server, it creates a CKModifyRecordsOperation.
 * If that operation comes back with an error from the CloudKit Framework, then YapDatabaseCloudKit automatically
 * suspends itself, and forwards the error to you via the OperationErrorBlock.
 * 
 * It's your job to look at the errorCode, decide what to do, and resume YapDatabaseCloudKit when ready.
 * 
 * For more information, please see the wiki:
 * https://github.com/yapstudios/YapDatabase/wiki/YapDatabaseCloudKit#OperationErrorBlock
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
 * 
 * For more information & sample code, please see the wiki:
 * https://github.com/yapstudios/YapDatabase/wiki/YapDatabaseCloudKit#The_databaseIdentifier
**/
typedef CKDatabase * _Nullable (^YapDatabaseCloudKitDatabaseIdentifierBlock)(NSString *databaseIdentifier);

NS_ASSUME_NONNULL_END
