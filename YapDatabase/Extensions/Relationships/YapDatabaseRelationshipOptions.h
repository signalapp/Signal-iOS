#import <Foundation/Foundation.h>
#import "YapWhitelistBlacklist.h"

/**
 * Welcome to YapDatabase!
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

typedef NSData* (^YapDatabaseRelationshipFilePathEncryptor)(NSString *dstFilePath);
typedef id (^YapDatabaseRelationshipFilePathDecryptor)(NSData *data);


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
@property (nonatomic, strong, readwrite) YapWhitelistBlacklist *allowedCollections;

/**
 * The relationship extension allows you to create relationships between objects in the database & files on disk.
 * This allows you to use the relationship extension to automatically delete files
 * when their associated object(s) is/are removed from the database.
 * 
 * However, you may not want this information stored in plaintext.
 * For example:
 * - you're encrypting the objects you store to the database via the serializer & deserializer
 * - you want to use the relationship extension in order to take advantage of auto file deletion
 * - but you don't want to store the filepath in plaintext for security reasons
 * 
 * You must set both the destinationFilePathEncryptor & destinationFilePathDecryptor.
 * 
 * If the destinationFilePathEncryptor returns nil for any filePath, then that filePath will be stored in plaintext.
 * Otherwise the returned data will be stored as a blob.
**/
@property (nonatomic, strong, readwrite) YapDatabaseRelationshipFilePathEncryptor destinationFilePathEncryptor;
@property (nonatomic, strong, readwrite) YapDatabaseRelationshipFilePathDecryptor destinationFilePathDecryptor;


@end
