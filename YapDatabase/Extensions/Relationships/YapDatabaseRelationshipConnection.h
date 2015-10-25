#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionConnection.h"

@class YapDatabaseRelationship;

NS_ASSUME_NONNULL_BEGIN

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yapstudios/YapDatabase/wiki
 *
 * The YapDatabaseRelationship extension allow you to create relationships between objects,
 * and configure automatic deletion rules.
 *
 * For tons of information about this extension, see the wiki article:
 * https://github.com/yapstudios/YapDatabase/wiki/Relationships
**/

@interface YapDatabaseRelationshipConnection : YapDatabaseExtensionConnection

/**
 * Returns the parent view instance.
**/
@property (nonatomic, strong, readonly) YapDatabaseRelationship *relationship;

@end

NS_ASSUME_NONNULL_END
