#import <Foundation/Foundation.h>

#import "YapDatabaseRelationshipEdge.h"
#import "YapWhitelistBlacklist.h"

NS_ASSUME_NONNULL_BEGIN

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

/**
 * The FileURLSerializer & FileURLDeserializer are used to convert between NSURL and the (serialized) blob
 * (of bytes) that goes into the database.
 * 
 * By default the system converts the NSURL to a "bookmark" so that,
 * even if the file is moved, the deserialized NSURL will point to the new filePath.
 * 
 * You can override this behavior to achieve alternative goals.
 * 
 * @see defaultFileURLSerializer
 * @see defaultFileURLDeserializer
**/
typedef NSData* _Nullable (^YapDatabaseRelationshipFileURLSerializer)(YapDatabaseRelationshipEdge *edge);
typedef NSURL* _Nullable (^YapDatabaseRelationshipFileURLDeserializer)(YapDatabaseRelationshipEdge *edge, NSData *data);

/**
 * Starting with v2.8, YapDatabaseRelationship extension uses NSURL to represent destination files.
 *
 * Prior to this, it used string-based file paths.
 * These proved especially brittle after Apple started moving app folders around in iOS (~ Xcode 6 & iOS 8).
 *
 * During the upgrade process (performed when the extension is registered),
 * the migration block can be used to convert previous filePaths to NSURL's.
 *
 * Only one of the parameters will be non-nil.
 *
 * @param filePath
 *   The original filePath that was given to the relationship extension
 * 
 * @param data
 *   The encrypted filePath, generated from a previously configured filePathEncryption block.
**/
typedef NSURL* _Nullable (^YapDatabaseRelationshipMigration)(NSString *_Nullable filePath, NSData *_Nullable data);


/**
 * This class allows for various customizations to the YapDatabaseRelationship extension.
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
@property (nonatomic, strong, readwrite, nullable) YapWhitelistBlacklist *allowedCollections;

/**
 * The relationship extension allows you to create relationships between objects in the database & files on disk.
 * This allows you to use the relationship extension to automatically delete files
 * when their associated object(s) is/are removed from the database.
 * 
 * The default values are 'defaultFileURLSerializer' & 'defaultFileURLDeserializer'.
 * 
 * @see defaultFileURLSerializer
 * @see defaultFileURLDeserializer
**/
@property (nonatomic, strong, readwrite) YapDatabaseRelationshipFileURLSerializer fileURLSerializer;
@property (nonatomic, strong, readwrite) YapDatabaseRelationshipFileURLDeserializer fileURLDeserializer;

/**
 * Starting with v2.8, YapDatabaseRelationship extension uses NSURL to represent destination files.
 * 
 * Prior to this, it used string-based file paths.
 * These proved especially brittle after Apple started moving app folders around in iOS (~ Xcode 6 & iOS 8).
 *
 * During the upgrade process (performed when the extension is registered),
 * the migration block can be used to convert previous filePaths to NSURL's.
 * 
 * Also, previous versions supported encrypting/decrypting the filePath.
 * If that was used, then it's important you implement your own migration block to perform the required decryption.
 * 
 * The default value is 'defaultMigration'.
 *
 * @see defaultMigration
**/
@property (nonatomic, strong, readwrite) YapDatabaseRelationshipMigration migration;

/**
 * Apple recommends persisting file locations using bookmarks.
 * 
 * From their documentation on the topic: https://goo.gl/0Uqn5J
 *
 *   If you want to save the location of a file persistently, use the bookmark capabilities of NSURL.
 *   A bookmark is an opaque data structure, enclosed in an NSData object, that describes the location of a file.
 *   Whereas path and file reference URLs are potentially fragile between launches of your app,
 *   a bookmark can usually be used to re-create a URL to a file even in cases where the file was moved or renamed.
 * 
 * The default serializer will attempt to use the bookmark capabilities of NSURL.
 * If this fails because the file doesn't exist, the serializer will fallback to a hybrid binary plist system.
 * It will look for a parent directory that does exist, generate a bookmark of that,
 * and store the remainder as a relative path.
 *
 * You can use your own serializer/deserializer if you need extra features.
**/
+ (YapDatabaseRelationshipFileURLSerializer)defaultFileURLSerializer;
+ (YapDatabaseRelationshipFileURLDeserializer)defaultFileURLDeserializer;

/**
 * For iOS:
 * 
 *   An optimistic migration is performed.
 *   This method inspects the filePath to determine what the relative path of the file was originally.
 *   It then uses this relativePath to generate a NSURL based on the current app directory.
 *   If this actually points to an existing file, and the prevoius filePath does not,
 *   then the (previously broken) filePath is automatically replaced by the generated NSURL in the app directory.
 * 
 * For Mac OS X - a simplistic migration is performed.
 *
 *   A simplistic migration is performed - simply converts string-based filePath's to NSURL's.
**/
+ (YapDatabaseRelationshipMigration)defaultMigration;

@end

NS_ASSUME_NONNULL_END
