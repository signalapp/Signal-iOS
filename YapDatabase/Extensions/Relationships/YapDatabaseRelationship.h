#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"

#import "YapDatabaseRelationshipNode.h"
#import "YapDatabaseRelationshipEdge.h"
#import "YapDatabaseRelationshipConnection.h"
#import "YapDatabaseRelationshipTransaction.h"

/**
 * ...
**/
@interface YapDatabaseRelationship : YapDatabaseExtension

- (id)init;

- (id)initWithVersion:(int)version;

//- (id)initWithVersion:(int)version options:(YapDatabaseRelationshipOptions *)options;

@end
