/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>
#import "YapWhitelistBlacklist.h"


@interface YapDatabaseCloudCoreOptions : NSObject <NSCopying>

/**
 * You can configure the extension to pre-filter all but a subset of collections.
 *
 * The primary motivation for this is to reduce the overhead when first setting up the extension.
 * For example, if you're only syncing objects from a single collection,
 * then you could specify that collection here. So when the extension first populates itself,
 * it will enumerate over just the allowedCollections, as opposed to enumerating over all collections.
 * And enumerating a small subset of the entire database during initial setup can improve speed,
 * especially with larger databases.
 *
 * In addition to reducing the overhead during initial setup,
 * the allowedCollections will pre-filter while you're making changes to the database.
 * So if you add a new object to the database, and the associated collection isn't in allowedCollections,
 * then the HandlerBlock will never be invoked, and the extension will act as if the block returned nil.
 *
 * For all rows whose collection is in the allowedCollections, the extension acts normally.
 * So the HandlerBlock would still be invoked as normal.
 *
 * The default value is nil.
**/
@property (nonatomic, strong, readwrite) YapWhitelistBlacklist *allowedCollections;

/**
 * Allows you to enforce which type of operations are allowed for this instance.
 * 
 * This is primarily helpful for:
 * - subclasses of YapDatabaseCloudCore, in order to enforce certain types of supported classes
 * - as a debugging tool, especially when transitioning to a different operation class
 *
 * The default value is nil.
**/
@property (nonatomic, copy, readwrite) NSSet *allowedOperationClasses;

/**
 * YapDatabaseCloudCore supports tracking the association between items in the database & URI's in the cloud.
 * That is, it contains various logic to store a many-to-many mapping of:
 *
 * (local collection/key tuple) <-> (cloudURI)
 *
 * If you choose to disable attach/detach support (by setting this value to NO) then:
 * - the CloudCore system won't bother creating the underlying table in sqlite
 * - the CloudCore system will throw an exception if you try to invoke one of the associated methods
 *
 * The default value is YES.
**/
@property (nonatomic, assign, readwrite) BOOL enableAttachDetachSupport;

/**
 * Most YapDatabaseCloudCoreOperation classes support automatically attaching a cloudURI
 * to the associated collection/key tuple. For example, YDBCloudCoreFileOperations can attach the filePath.
 *
 * @see [YapDatabaseCloudCoreFileOperation shouldAttach]
 *
 * The default value is YES.
 *
 * Note: This is ignored if attachDetachSupport is disabled.
**/
@property (nonatomic, assign, readwrite) BOOL implicitAttach;

/**
 * YapDatabaseCloudCore supports associating "tags" with cloudURI's.
 * This is primarily designed to assist you in storing information associated with sync, such as eTag values.
 *
 * This support is optional, as you may find it more convenient to store such values directly in your objects.
 * Thus, it can be disabled if you have no need for it.
 * 
 * If you choose to disable tag support (by setting this value to NO) then:
 * - the CloudCore system won't bother creating the underlying table in sqlite
 * - the CloudCore system will throw an exception if you try to invoke one of the associated methods
 *
 * The default value is YES.
**/
@property (nonatomic, assign, readwrite) BOOL enableTagSupport;

@end
