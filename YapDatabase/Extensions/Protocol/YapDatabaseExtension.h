#import <Foundation/Foundation.h>

#import "YapDatabaseExtensionConnection.h"
#import "YapDatabaseExtensionTransaction.h"


@interface YapDatabaseExtension : NSObject

/**
 * After an extension has been successfully registered with a database,
 * the registeredName property will be set by the database.
**/
@property (atomic, copy, readonly) NSString *registeredName;

@end
