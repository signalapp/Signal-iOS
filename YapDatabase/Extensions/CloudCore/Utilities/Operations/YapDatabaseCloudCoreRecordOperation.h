/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>
#import "YapDatabaseCloudCoreFileOperation.h"

/**
 * A record operation represents a file that is backed by key/value pairs.
 * For example, the file may simply be a JSON dictionary of key/value pairs from an object.
**/
@interface YapDatabaseCloudCoreRecordOperation : YapDatabaseCloudCoreFileOperation <NSCoding>

/**
 * UPLOAD operation to create/modify a record in the cloud.
**/
+ (YapDatabaseCloudCoreRecordOperation *)uploadWithCloudPath:(YapFilePath *)cloudPath;

/**
 * When you make changes to a record, you should store the original key/value pairs.
 * That is, the key(s) that were changed along with their values prior to the change.
 *
 * The importance of this information is made clear within the context of the mergeRecordBlock.
 * This parameter will be made available via the mergeRecordInfo parameter of the mergeRecordBlock.
 *
 * This dictionary will be stored with the operation in the database.
**/
@property (nonatomic, copy, readwrite) NSDictionary *originalValues;

/**
 * When you make changes to a record, you should store the updated key/value pairs.
 * That is, the key(s) that were changed along with their new values.
 * 
 * The importance of this information is made clear within the context of the mergeRecordBlock.
 * This parameter will be made available via the mergeRecordInfo parameter of the mergeRecordBlock.
 *
 * Typically only the dictionary keys are stored with the operation in the database (depending on the situation).
**/
@property (nonatomic, copy, readwrite) NSDictionary *updatedValues;

@end
