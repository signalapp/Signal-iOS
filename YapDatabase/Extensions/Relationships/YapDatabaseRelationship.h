#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"

#import "YapDatabaseRelationshipNode.h"
#import "YapDatabaseRelationshipEdge.h"
#import "YapDatabaseRelationshipOptions.h"
#import "YapDatabaseRelationshipConnection.h"
#import "YapDatabaseRelationshipTransaction.h"

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * The YapDatabaseRelationship extension allow you to create relationships between objects,
 * and configure automatic deletion rules.
 *
 * For tons of information about this extension, see the wiki article:
 * https://github.com/yaptv/YapDatabase/wiki/Relationships
**/

@interface YapDatabaseRelationship : YapDatabaseExtension

- (id)init;

- (id)initWithVersion:(int)version;

- (id)initWithVersion:(int)version options:(YapDatabaseRelationshipOptions *)options;

@end
