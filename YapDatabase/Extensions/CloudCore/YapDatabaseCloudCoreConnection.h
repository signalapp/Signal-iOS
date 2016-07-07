/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionConnection.h"

@class YapDatabaseCloudCore;


@interface YapDatabaseCloudCoreConnection : YapDatabaseExtensionConnection

/**
 * Returns the parent instance.
**/
@property (nonatomic, strong, readonly) YapDatabaseCloudCore *cloudCore;

@end
