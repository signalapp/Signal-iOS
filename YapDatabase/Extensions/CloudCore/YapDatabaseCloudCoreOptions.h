/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>
#import "YapWhitelistBlacklist.h"


@interface YapDatabaseCloudCoreOptions : NSObject <NSCopying>

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
 * YapDatabaseCloudCore supports storing various "tags" related to cloud syncing, such as eTag values.
 *
 * You may find this useful.
 * Or you may find it more convenient to store such values directly in your objects.
 *
 * The default value is NO (disabled).
**/
@property (nonatomic, assign, readwrite) BOOL enableTagSupport;

/**
 * YapDatabaseCloudCore supports tracking the association between items in the database & URI's in the cloud.
 * That is, it contains various logic to store a many-to-many mapping of:
 *
 * (local collection/key tuple) <-> (cloudURI)
 *
 * The default value is NO (disabled).
**/
@property (nonatomic, assign, readwrite) BOOL enableAttachDetachSupport;

@end
