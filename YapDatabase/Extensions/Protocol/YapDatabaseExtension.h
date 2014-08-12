#import <Foundation/Foundation.h>

#import "YapDatabaseExtensionConnection.h"
#import "YapDatabaseExtensionTransaction.h"

@class YapDatabase;


@interface YapDatabaseExtension : NSObject

/**
 * After an extension has been successfully registered with a database,
 * the registeredName property will be set by the database.
**/
@property (atomic, copy, readonly) NSString *registeredName;

/**
 * After an extension has been successfully registered with a database,
 * the registeredDatabase property will be set to that database.
**/
@property (atomic, weak, readonly) YapDatabase *registeredDatabase;

@end
