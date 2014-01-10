#import <Foundation/Foundation.h>

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

@interface YapDatabaseRelationshipOptions : NSObject <NSCopying>

/**
 * You can optionally completely disable the YapDatabaseRelationshipProtocol.
 * 
 * If you don't use it at all (i.e. you manually manage all graph edges),
 * then disabling the protocol, and its related processing, can reduce overhead.
 *
 * The default value is NO.
**/
@property (nonatomic, assign, readwrite) BOOL disableYapDatabaseRelationshipNodeProtocol;

/**
 * You can configure the extension to pre-filter all but a subset of collections.
 *
 * The primary motivation for this is to reduce the overhead when populating the graph.
 * That is, when you first create the relationship extension, it will automatically enumerate all objects
 * in the database and check to see if any of them implement the YapDatabaseRelationshipNode protocol.
 * If there is only a single collection which includes objects implementing the YapDatabaseRelationshipNode protoco,
 * then you could specify that collection here. So when the extension first populates itself,
 * it will enumerate over just the allowedCollections, as opposed to enumerating over all collections.
 * And enumerating a small subset of the entire database during graph population can improve speed,
 * especially with larger databases.
 * 
 * In addition to reducing the overhead when first populating the graph,
 * the allowedCollections will pre-filter while you're making changes to the database.
 * So if you add a new object to the database, and the associated collection isn't in allowedCollections,
 * then the extension will skip any associated processing that would normally occur. (Things like checking to see
 * if the object implements the YapDatabaseRelationshipNode protocol, and checking to see if there were previously
 * any associated protocol edges for the object.)
 *
 * For all rows whose collection is in the allowedCollections, the extension works normally.
 *
 * Note: If you disable the YapDatabaseRelationshipNode protocol, then this configuration option is ignored
 * because it already skips all associated processing.
 *
 * The default value is nil.
**/
@property (nonatomic, copy, readwrite) NSSet *allowedCollections;

@end
