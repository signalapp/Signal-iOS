#import <Foundation/Foundation.h>

#import "YapDatabaseExtensionTypes.h"
#import "YapDatabaseExtensionConnection.h"
#import "YapDatabaseExtensionTransaction.h"

@class YapDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseExtension : NSObject

/**
 * After an extension has been successfully registered with a database,
 * the registeredName property will be set by the database.
**/
@property (atomic, copy, readonly, nullable) NSString *registeredName;

/**
 * After an extension has been successfully registered with a database,
 * the registeredDatabase property will be set to that database.
**/
@property (atomic, weak, readonly, nullable) YapDatabase *registeredDatabase;

@end

NS_ASSUME_NONNULL_END
