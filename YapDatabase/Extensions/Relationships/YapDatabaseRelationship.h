#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"

#import "YapDatabaseRelationshipNode.h"
#import "YapDatabaseRelationshipEdge.h"
#import "YapDatabaseRelationshipOptions.h"
#import "YapDatabaseRelationshipConnection.h"
#import "YapDatabaseRelationshipTransaction.h"

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

@interface YapDatabaseRelationship : YapDatabaseExtension

- (id)init;

- (id)initWithVersionTag:(nullable NSString *)versionTag;

- (id)initWithVersionTag:(nullable NSString *)versionTag options:(nullable YapDatabaseRelationshipOptions *)options;

/**
 * The versionTag assists in making changes to the extension or any objects that implement YapDatabaseRelationshipNode.
 *
 * For example, say you have existing objects that implement the YapDatabaseRelationshipNode protocol.
 * And you decide to add additional relationship connections from within the yapDatabaseRelationshipEdges method
 * of some of your objects. All you have to do is change the versionTag. And next time you run the app,
 * the YapDatabaseRelationship extension will notice the different versionTag, and will then automatically
 * remove all protocol edges from the database, and automatically repopulate its list of protocol edges
 * by enumerating the nodes in the database.
**/
@property (nonatomic, copy, readonly) NSString *versionTag;

/**
 * The options that were used to initialize the instance.
**/
@property (nonatomic, copy, readonly) YapDatabaseRelationshipOptions *options;

@end

NS_ASSUME_NONNULL_END
