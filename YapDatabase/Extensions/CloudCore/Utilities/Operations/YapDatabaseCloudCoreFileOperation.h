/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>
#import "YapDatabaseCloudCoreOperation.h"
#import "YapFilePath.h"


extern NSString *const YDBCloudOperationType_Upload;    // @"Upload"
extern NSString *const YDBCloudOperationType_Delete;    // @"Delete"
extern NSString *const YDBCloudOperationType_Move;      // @"Move"
extern NSString *const YDBCloudOperationType_Copy;      // @"Copy"
extern NSString *const YDBCloudOperationType_CreateDir; // @"CreateDir"

/**
 * A file operation represents a generic operation involving a "file" in the cloud with a specific URL.
 * 
 * There are 5 basic types of file operations:
 * - Upload    - uploads a new or modified file to the cloud
 * - Delete    - deletes a file from the cloud
 * - Move      - moves a file in the cloud from one URL to another
 * - Copy      - copies a file in the cloud from one URL to another
 * - CreateDir - creates a directory in the cloud
 *
 * In addition to this, you'll likely want to create domain-specific types. For example:
 * - Share
 * - SetPrivileges
**/
@interface YapDatabaseCloudCoreFileOperation : YapDatabaseCloudCoreOperation <NSCoding>

#pragma mark Creation

/**
 * UPLOAD operation to create/modify a file in the cloud.
 * 
 * You need to set the (data || fileURL || stream) property before the operation can start.
 * You can do so immediately, or you can do so at a later time (a "delayed" upload).
 * 
 * The idea behind a "delayed upload" is that you create the operation immediately,
 * with the proper cloudPath and other attributes,
 * and then start some asynchronous process to generate the data or file.
 * Once it's available, you set the data/fileURL/stream property,
 * and the operation will automatically be marked as "ready" (internally).
 *
 * Important:
 *   Keep in mind that if you don't eventually set the data/fileURL/stream property,
 *   then the operation will never become ready. Which means that it will block the
 *   entire pipeline, and the whole sync system will freeze.
 *   So if your asynchronous process can fail, be sure to properly handle it.
 *   This might mean restarting the process, or skipping the corresponding operation.
**/
+ (YapDatabaseCloudCoreFileOperation *)uploadWithCloudPath:(YapFilePath *)cloudPath;

/**
 * DELETE operation to remove a file from the cloud.
**/
+ (YapDatabaseCloudCoreFileOperation *)deleteWithCloudPath:(YapFilePath *)cloudPath;

/**
 * MOVE operation.
 * 
 * The sourcePath will be moved to the targetPath.
**/
+ (YapDatabaseCloudCoreFileOperation *)moveWithCloudPath:(YapFilePath *)sourcePath
                                         targetCloudPath:(YapFilePath *)targetPath;

/**
 * COPY operation.
 * 
 * The sourcePath will be copied to the targetPath.
**/
+ (YapDatabaseCloudCoreFileOperation *)copyWithCloudPath:(YapFilePath *)sourcePath
                                         targetCloudPath:(YapFilePath *)targetPath;

/**
 * CREATE_DIR operation.
**/
+ (YapDatabaseCloudCoreFileOperation *)createDirectoryWithCloudPath:(YapFilePath *)cloudPath;

/**
 * CUSTOM operations.
**/
+ (YapDatabaseCloudCoreFileOperation *)operationWithType:(NSString *)type cloudPath:(YapFilePath *)cloudPath;
+ (YapDatabaseCloudCoreFileOperation *)operationWithType:(NSString *)type
                                               cloudPath:(YapFilePath *)cloudPath
                                         targetCloudPath:(YapFilePath *)targetCloudPath;

#pragma mark Names

/**
 * Every operation has a name, which is dynamically generated from the operation's attributes.
 * Names are designed to assist with dependencies.
 *
 * @see name
**/

+ (NSString *)nameForUploadWithCloudPath:(YapFilePath *)cloudPath;
+ (NSString *)nameForDeleteWithCloudPath:(YapFilePath *)cloudPath;
+ (NSString *)nameForMoveWithCloudPath:(YapFilePath *)cloudPath targetCloudPath:(YapFilePath *)targetCloudPath;
+ (NSString *)nameForCopyWithCloudPath:(YapFilePath *)cloudPath targetCloudPath:(YapFilePath *)targetCloudPath;

+ (NSString *)nameForType:(NSString *)type cloudPath:(YapFilePath *)cloudPath;
+ (NSString *)nameForType:(NSString *)type cloudPath:(YapFilePath *)cloudPath
                                     targetCloudPath:(YapFilePath *)targetCloudPath;

#pragma mark Instance

/**
 * Every operation should have a "type", which helps identify what kind of operation it is.
 * 
 * The default operation types are defined as constants:
 * - YDBCloudOperationType_Upload
 * - YDBCloudOperationType_Delete
 * - YDBCloudOperationType_Move
 * - YDBCloudOperationType_Copy
 * - YDBCloudOperationType_CreateDir
 * 
 * You can also define your own custom types for domain-specific operations.
 * 
 * @see isOperationType:
 * @see isUploadOperation
 * @see isDeleteOperation
 * @see isMoveOperation
 * @see isCopyOperation
 * @see isCreateDirOperation
**/
@property (nonatomic, copy, readwrite) NSString *type;

/**
 * The cloudPath is available for all operations.
 * The targetCloudPath is only available for move & copy operations (and custom operations that define it).
 * 
 * A cloudPath is the relative path of the URL. E.g. "/contacts/uuid.json".
 * The upload code would then combine this with the base URL of the cloud service.
**/
@property (nonatomic, copy, readwrite) YapFilePath *cloudPath;
@property (nonatomic, copy, readwrite) YapFilePath *targetCloudPath;

/**
 * Every operation has a name which is derived from the operation's attributes.
 * Specifically, the name is derived as follows:
 * 
 * if (targetCloudPath)
 *   [NSString stringWithFormat@"%@ %@ -> %@", type, cloudPath, targetCloudPath];
 * else
 *   [NSString stringWithFormat@"%@ %@", type, cloudPath];
 * 
 * Names are designed to assist with dependencies.
 * 
 * For example, suppose you have 2 operations: opA & opB
 * You want opB to depend on opA, so that opA comletes before opB starts.
 * There are 2 ways in which you can accomplish this:
 * 
 * 1. [opB addDependency:opA.uuid]
 * 2. [opB addDependency:opA.name]
 * 
 * Option 1 is always the preferred method, but is only convenient if you happen to have the opA instance on hand.
 * 
 * Option 2 can easily be generated even without opB, by simply using the various class name methods.
 * - [YapDatabaseCloudCoreFileOperation nameForUploadWithCloudPath:]
 * - [YapDatabaseCloudCoreFileOperation nameForDeleteWithCloudPath:]
 * - [YapDatabaseCloudCoreFileOperation nameForMoveWithCloudPath:targetCloudPath:]
 * - [YapDatabaseCloudCoreFileOperation nameForCopyWithCloudPath:targetCloudPath:]
 * - [YapDatabaseCloudCoreFileOperation nameForType:cloudPath:]
 * - [YapDatabaseCloudCoreFileOperation nameForType:cloudPath:targetCloudPath:]
**/
@property (nonatomic, readonly) NSString *name;

/**
 * When shouldAttach is @(YES), then submitting an operation attaches the
 * associated collection/key tuple to the cloudPath.
 *
 * When shouldAttach is @(NO), then no attaching occurs.
 * 
 * When shouldAttach is nil, then attaching depends upon the configured value
 * of YapDatabaseCloudCoreOptions.implicitAttach (set during YapDatabaseCloudCore init).
 * If YapDatabaseCloudCoreOptions.implicitAttach is YES, then attaching will occur for 
 * Upload & CreateDir operations, but will not occur for any other operation type.
 *
 * For more information about 'attach':
 * @see [YapDatabaseCloudCoreTransaction attachCloudURI:forKey:inCollection:]
 * 
 * Mutability:
 *   Before the operation has been handed over to YapDatabaseCloudCore, this property is mutable.
 *   However, once the operation has been handed over to YapDatabaseCloudCore, it becomes immutable.
**/
@property (nonatomic, assign, readwrite) NSNumber *shouldAttach;


#pragma mark Convenience

- (BOOL)isOperationType:(NSString *)type;

@property (nonatomic, readonly) BOOL isUploadOperation;
@property (nonatomic, readonly) BOOL isDeleteOperation;
@property (nonatomic, readonly) BOOL isMoveOperation;
@property (nonatomic, readonly) BOOL isCopyOperation;
@property (nonatomic, readonly) BOOL isCreateDirOperation;
@property (nonatomic, readonly) BOOL isCustomOperation;

@end
