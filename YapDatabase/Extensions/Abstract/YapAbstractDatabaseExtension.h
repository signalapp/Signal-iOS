#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseExtensionConnection.h"
#import "YapAbstractDatabaseExtensionTransaction.h"


@interface YapAbstractDatabaseExtension : NSObject

/**
 * After an extension has been successfully registered with a database,
 * the registeredName property will be set by the database.
**/
@property (atomic, copy, readonly) NSString *registeredName;

@end
