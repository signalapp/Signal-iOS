#import <Foundation/Foundation.h>

/**
 * Welcome to YapDatabase!
 *
 * The project page has a wealth of documentation if you have any questions.
 * https://github.com/yapstudios/YapDatabase
 *
 * If you're new to the project you may want to visit the wiki.
 * https://github.com/yapstudios/YapDatabase/wiki
 * 
 * This class provides extra configuration options that may be passed to YapDatabase.
 * The configuration options provided by this class are advanced (beyond the basic setup options).
**/

typedef NS_ENUM(NSInteger, YapDatabaseCorruptAction) {
    YapDatabaseCorruptAction_Fail   = 0,
    YapDatabaseCorruptAction_Rename = 1,
    YapDatabaseCorruptAction_Delete = 2,
};

typedef NS_ENUM(NSInteger, YapDatabasePragmaSynchronous) {
	YapDatabasePragmaSynchronous_Off    = 0,
	YapDatabasePragmaSynchronous_Normal = 1,
	YapDatabasePragmaSynchronous_Full   = 2,
};

#ifdef SQLITE_HAS_CODEC
typedef NSData* (^YapDatabaseCipherKeyBlock)(void);
#endif

@interface YapDatabaseOptions : NSObject <NSCopying>

/**
 * How should YapDatabase proceed if it is unable to open an existing database file
 * because sqlite finds it to be corrupt?
 *
 * - YapDatabaseCorruptAction_Fail
 *     The YapDatabase alloc/init operation will fail, and the init method will ultimately return nil.
 * 
 * - YapDatabaseCorruptAction_Rename
 *     The YapDatabase init operation will succeed, a new database file will be created,
 *     and the corrupt file will be renamed by adding the suffix ".X.corrupt", where X is a number.
 *
 * - YapDatabaseCorruptAction_Delete
 *     The YapDatabase init operation will succeed, a new database file will be created,
 *     and the corrupt file will be deleted.
 *
 * The default value is YapDatabaseCorruptAction_Rename.
**/
@property (nonatomic, assign, readwrite) YapDatabaseCorruptAction corruptAction;

/**
 * Allows you to configure the sqlite "PRAGMA synchronous" option.
 * 
 * For more information, see the sqlite docs:
 * https://www.sqlite.org/pragma.html#pragma_synchronous
 * https://www.sqlite.org/wal.html#fast
 * 
 * Note that YapDatabase uses sqlite in WAL mode.
 *
 * The default value is YapDatabasePragmaSynchronous_Full.
**/
@property (nonatomic, assign, readwrite) YapDatabasePragmaSynchronous pragmaSynchronous;

/**
 * Allows you to configure the sqlite "PRAGMA journal_size_limit" option.
 * 
 * For more information, see the sqlite docs:
 * http://www.sqlite.org/pragma.html#pragma_journal_size_limit
 * 
 * Note that YapDatabase uses sqlite in WAL mode.
 * 
 * The default value is zero,
 * meaning that every checkpoint will reduce the WAL file to its minimum size (if possible).
**/
@property (nonatomic, assign, readwrite) NSInteger pragmaJournalSizeLimit;

#ifdef SQLITE_HAS_CODEC
/**
 * Set a block here that returns the key for the SQLCipher database.
 *
 * This is the key that will be passed to SQLCipher via the sqlite3_key method:
 * https://www.zetetic.net/sqlcipher/sqlcipher-api/#sqlite3_key
 * 
 * This block allows you can fetch the passphrase from the keychain (or elsewhere)
 * only when you need it, instead of persisting it in memory.
 *
 * You must use the 'YapDatabase/SQLCipher' subspec
 * in your Podfile for this option to take effect.
 **/
@property (nonatomic, copy) YapDatabaseCipherKeyBlock cipherKeyBlock;
#endif

@end
