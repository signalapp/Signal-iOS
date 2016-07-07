/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionTypes.h"

@class YDBCloudCoreRestoreInfo;
@class YDBCloudCoreMergeRecordInfo;

@class YapDatabaseCloudCorePipeline;
@class YapDatabaseCloudCoreOperation;
@class YapDatabaseCloudCoreRecordOperation;

@class YapDatabaseReadTransaction;
@class YapDatabaseReadWriteTransaction;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Handler (required)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The Handler block is used to generate cloud operations.
 * That is, it allows you to convert object changes into cloud operations that push content to the cloud.
 * 
 * <LINK GOES HERE>
**/
@interface YapDatabaseCloudCoreHandler : NSObject

typedef id YapDatabaseCloudCoreHandlerBlock; // One of the YapDatabaseCloudCoreHandlerX types below.

typedef void (^YapDatabaseCloudCoreHandlerWithKeyBlock)
               (YapDatabaseReadTransaction *transaction, NSMutableArray *operations,
                NSString *collection, NSString *key);

typedef void (^YapDatabaseCloudCoreHandlerWithObjectBlock)
               (YapDatabaseReadTransaction *transaction, NSMutableArray *operations,
                NSString *collection, NSString *key, id object);

typedef void (^YapDatabaseCloudCoreHandlerWithMetadataBlock)
               (YapDatabaseReadTransaction *transaction, NSMutableArray *operations,
                NSString *collection, NSString *key, id metadata);

typedef void (^YapDatabaseCloudCoreHandlerWithRowBlock)
               (YapDatabaseReadTransaction *transaction, NSMutableArray *operations,
                NSString *collection, NSString *key, id object, id metadata);

+ (instancetype)withKeyBlock:(YapDatabaseCloudCoreHandlerWithKeyBlock)block;
+ (instancetype)withObjectBlock:(YapDatabaseCloudCoreHandlerWithObjectBlock)block;
+ (instancetype)withMetadataBlock:(YapDatabaseCloudCoreHandlerWithMetadataBlock)block;
+ (instancetype)withRowBlock:(YapDatabaseCloudCoreHandlerWithRowBlock)block;

+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops keyBlock:(YapDatabaseCloudCoreHandlerWithKeyBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops objectBlock:(YapDatabaseCloudCoreHandlerWithObjectBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops metadataBlock:(YapDatabaseCloudCoreHandlerWithMetadataBlock)block;
+ (instancetype)withOptions:(YapDatabaseBlockInvoke)ops rowBlock:(YapDatabaseCloudCoreHandlerWithRowBlock)block;

@property (nonatomic, strong, readonly) YapDatabaseCloudCoreHandlerBlock block;
@property (nonatomic, assign, readonly) YapDatabaseBlockType             blockType;
@property (nonatomic, assign, readonly) YapDatabaseBlockInvoke           blockInvokeOptions;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Delete Handler (optional)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The the delete handler is used to generate delete operations.
 * 
 * @param operations
 *   Any operations you wish to add to the queue must be added to this array.
 * 
 * @param mappings
 *   If attach/detach support is enabled, this contains a list of the cloudURI's that the (to be) deleted
 *   row was attached to. Specifically, each key is a cloudURI that was attached to the row being deleted.
 *   And each value is the remaining retainCount of the URI. In other words, the number of remaining rows
 *   in the database that are attached to the cloudURI.
**/
@interface YapDatabaseCloudCoreDeleteHandler : NSObject

typedef id YapDatabaseCloudCoreDeleteHandlerBlock; // One of the YapDatabaseCloudCoreHandlerX types below.

typedef void (^YapDatabaseCloudCoreDeleteHandlerWithKeyBlock)
  (YapDatabaseReadTransaction *transaction, NSMutableArray *operations, NSDictionary<NSString*, NSNumber*> *mappings,
   NSString *collection, NSString *key);

typedef void (^YapDatabaseCloudCoreDeleteHandlerWithObjectBlock)
  (YapDatabaseReadTransaction *transaction, NSMutableArray *operations, NSDictionary<NSString*, NSNumber*> *mappings,
   NSString *collection, NSString *key, id object);

typedef void (^YapDatabaseCloudCoreDeleteHandlerWithMetadataBlock)
  (YapDatabaseReadTransaction *transaction, NSMutableArray *operations, NSDictionary<NSString*, NSNumber*> *mappings,
   NSString *collection, NSString *key, id metadata);

typedef void (^YapDatabaseCloudCoreDeleteHandlerWithRowBlock)
  (YapDatabaseReadTransaction *transaction, NSMutableArray *operations, NSDictionary<NSString*, NSNumber*> *mappings,
   NSString *collection, NSString *key, id object, id metadata);

+ (instancetype)withKeyBlock:(YapDatabaseCloudCoreDeleteHandlerWithKeyBlock)block;
+ (instancetype)withObjectBlock:(YapDatabaseCloudCoreDeleteHandlerWithObjectBlock)block;
+ (instancetype)withMetadataBlock:(YapDatabaseCloudCoreDeleteHandlerWithMetadataBlock)block;
+ (instancetype)withRowBlock:(YapDatabaseCloudCoreDeleteHandlerWithRowBlock)block;

@property (nonatomic, strong, readonly) YapDatabaseCloudCoreDeleteHandlerBlock block;
@property (nonatomic, assign, readonly) YapDatabaseBlockType                   blockType;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Merge Record Block (required)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Merge Record Block
**/
typedef void (^YapDatabaseCloudCoreMergeRecordBlock)
    (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key,
     NSDictionary *remoteRecord, YapDatabaseCloudCoreRecordOperation *recordOperation);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operation Serialization & Deserialization (optional)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The default serializer/deserializer for operation objects is NSCoding.
 * 
 * This means that a recordOperation's 'originalValues' & 'updatedValues' properties will need to support NSCoding.
 * That is, the key/value pairs placed into these dictionaries will need to support NSCoding.
 * 
 * Since most common data types support NSCoding, this is a sensible default.
 * However, if NSCoding causes issues, it may be substitued for an alternative custom technique.
**/

typedef NSData* (^YDBCloudCoreOperationSerializer)(YapDatabaseCloudCoreOperation *operation);

typedef YapDatabaseCloudCoreOperation* (^YDBCloudCoreOperationDeserializer)(NSData *operationBlob);

