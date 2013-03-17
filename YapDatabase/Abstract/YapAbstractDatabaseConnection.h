#import <Foundation/Foundation.h>
#import "YapSharedCache.h"

@class YapAbstractDatabase;

typedef enum  {
	YapDatabaseConnectionFlushMemoryLevelNone     = 0,
	YapDatabaseConnectionFlushMemoryLevelMild     = 1,
	YapDatabaseConnectionFlushMemoryLevelModerate = 2,
	YapDatabaseConnectionFlushMemoryLevelFull     = 3,
} YapDatabaseConnectionFlushMemoryLevel;

/**
 * This base class is shared by YapDatabaseConnection and YapCollectionsDatabaseConnection.
 *
 * It provides the generic implementation of a database such as:
 * - common properties
 * - common initializers
 * - common setup code
 * - stub methods which are overriden by subclasses
**/
@interface YapAbstractDatabaseConnection : NSObject

/**
 * A database connection maintains a strong reference to its parent.
 *
 * This is to enforce the following core architecture rule:
 * A database instance cannot be deallocated if a corresponding connection is stil alive.
 *
 * If you use only a single connection,
 * it is sometimes convenient to retain an ivar only for the connection, and not the database itself.
**/
@property (nonatomic, strong, readonly) YapAbstractDatabase *abstractDatabase;

/**
 * Each database connection maintains an independent cache of deserialized objects.
 * This reduces the overhead of the deserialization process.
 * You can optionally configure the cache size, or disable it completely.
 *
 * The cache is properly kept in sync with the atomic snapshot architecture of the database system.
 *
 * By default the objectCache is enabled and has a limit of 40.
 *
 * You can configure the objectCache at any time, including within readBlocks or readWriteBlocks.
 * To disable the object cache entirely, set objectCacheEnabled to NO.
 * To use an inifinite cache size, set the objectCacheLimit to zero.
**/
@property (atomic, assign, readwrite) BOOL objectCacheEnabled;
@property (atomic, assign, readwrite) NSUInteger objectCacheLimit;

/**
 * Each database connection maintains an independent cache of deserialized metadata.
 * This reduces the overhead of the deserialization process.
 * You can optionally configure the cache size, or disable it completely.
 *
 * The cache is properly kept in sync with the atomic snapshot architecture of the database system.
 *
 * By default the metadataCache is enabled and has an infinite limit.
 *
 * You can configure the metadataCache at any time, including within readBlocks or readWriteBlocks.
 * To disable the metadata cache entirely, set metadataCacheEnabled to NO.
 * To use an inifinite cache size, set the metadataCacheLimit to zero.
**/
@property (atomic, assign, readwrite) BOOL metadataCacheEnabled;
@property (atomic, assign, readwrite) NSUInteger metadataCacheLimit;

#if TARGET_OS_IPHONE
/**
 * When a UIApplicationDidReceiveMemoryWarningNotification is received,
 * the code automatically invokes flushMemoryWithLevel and passes this set level.
 * 
 * The default value is YapDatabaseConnectionFlushMemoryLevelMild.
 * 
 * @see flushMemoryWithLevel:
**/
@property (atomic, assign, readwrite) int autoFlushMemoryLevel;
#endif

/**
 * This method may be used to flush the internal caches used by the connection,
 * as well as flushing pre-compiled sqlite statements.
 * Depending upon how often you use the database connection,
 * you may want to be more or less aggressive on how much stuff you flush.
 *
 * YapDatabaseConnectionFlushMemoryLevelNone (0):
 *     No-op. Doesn't flush any caches or anything from internal memory.
 * 
 * YapDatabaseConnectionFlushMemoryLevelMild (1):
 *     Flushes the object cache and metadata cache.
 * 
 * YapDatabaseConnectionFlushMemoryLevelModerate (2):
 *     Mild plus drops less common pre-compiled sqlite statements.
 * 
 * YapDatabaseConnectionFlushMemoryLevelFull (3):
 *     Full flush of all caches and removes all pre-compiled sqlite statements.
**/
- (void)flushMemoryWithLevel:(int)level;

@end
