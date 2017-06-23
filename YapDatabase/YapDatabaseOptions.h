#import <Foundation/Foundation.h>

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
typedef NSData *_Nonnull (^YapDatabaseCipherKeyBlock)(void);
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

/**
 * Allows you to configure the sqlite "PRAGMA page_size" option.
 * 
 * For more information, see the sqlite docs:
 * https://www.sqlite.org/pragma.html#pragma_page_size
 * 
 * The default page_size is traditionally 4096 on Apple systems.
 * 
 * Important: "It is not possible to change the database page size after entering WAL mode".
 * https://www.sqlite.org/wal.html
 *
 * And YapDatabase uses sqlite in WAL mode.
 * This means that if you intend to use a non-default page_size, you MUST configure the pragmaPageSize
 * before you first create the sqlite database file.
 * 
 * Example 1:
 * - sqlite database file does not exist
 * - configure pragmaPageSize
 * - initialize YapDatabase with corresponding YapDatabaseOptions
 * - page_size will be set according to configuration
 * 
 * Example 2:
 * - sqlite database file already exists
 * - configure pragmaPageSize
 * - initialize YapDatabase with corresponding YapDatabaseOptions
 * - page_size cannot be changed - it remains as it was before
 * 
 * The default value is zero, meaning the default page size will be used.
 * E.g. YapDatabase will not attempt to set an explicit page_size.
 * 
 * You can verify whether or not sqlite accepted your page_size configuration request via:
 * - [yapdbConnection pragmaPageSize]
**/
@property (nonatomic, assign, readwrite) NSInteger pragmaPageSize;

/**
 * Allows you to configure the sqlite "PRAGMA mmap_size" option.
 * 
 * For more information, see the sqlite docs:
 * https://www.sqlite.org/pragma.html#pragma_mmap_size
 * 
 * This option allows you to enable Memory Mapped I/O.
 * https://www.sqlite.org/mmap.html
 * 
 * The value is specified in BYTES.
 *
 * The default value is zero, meaning that Memory Mapped I/O is not used.
 * It is likely that you can achieve improved performance by setting this to a large value.
 * 
 * Note that memory mapping may not be available.
 * The feature was added to sqlite in version 3.7.17.
 * If using the built-in version of sqlite (with the OS), then this requires a minimum of:
 * - iOS 8.2
 * - Max OS X 10.10
 * 
 * For more information on SQLite versions that come pre-installed with the OS:
 * https://github.com/yapstudios/YapDatabase/wiki/SQLite-version-(bundled-with-OS)
 * 
 * Additionally, it appears that memory mapping is explicitly disabled in sqlite for iOS.
 * This can be seen by inspecting the sqlite.c source code file:
 * 
 * > #ifdef __APPLE__
 * > # include <TargetConditionals.h>
 * > # if TARGET_OS_IOS
 * > #   undef SQLITE_MAX_MMAP_SIZE
 * > #   define SQLITE_MAX_MMAP_SIZE 0
 * > # endif
 * > #endif
 *
 * It does, however, currently work for Mac OS X.
 * 
 * You can verify whether or not sqlite accepted your mmap_size configuration request via:
 * - [yapdbConnection pragmaMMapSize]
**/
@property (nonatomic, assign, readwrite) NSInteger pragmaMMapSize;

#ifdef SQLITE_HAS_CODEC
/**
 * Set a block here that returns the key for the SQLCipher database.
 *
 * This is the key that will be passed to SQLCipher via the sqlite3_key method:
 * https://www.zetetic.net/sqlcipher/sqlcipher-api/#sqlite3_key
 * 
 * This block allows you to fetch the passphrase from the keychain (or elsewhere)
 * only when you need it, instead of persisting it in memory.
 *
 * You must use the 'YapDatabase/SQLCipher' subspec
 * in your Podfile for this option to take effect.
 *
 * Important: If you do not set a cipherKeyBlock the database will NOT be configured with encryption.
**/
@property (nonatomic, copy, readwrite) YapDatabaseCipherKeyBlock cipherKeyBlock;

/**
 * Set the PBKDF2 iteration number for deriving the key to the SQLCipher database.
 *
 * This is the PBKDF2 iteration number that will be passed to SQLCipher via the 'kdf_iter' pragma.
 * This parameter will be used everytime the database is openened and you must not change it,
 * otherwise SQLCipher will not be able to decrypt it.
 * https://www.zetetic.net/sqlcipher/sqlcipher-api/#kdf_iter
 *
 * You must use the 'YapDatabase/SQLCipher' subspec
 * in your Podfile for this option to take effect.
 *
 * This parameter isn't compulsory to a SQLCipher database but it is useful if you want
 * to customize the iteration count (for performance reasons) of PBKDF.
 * Default is 64,000 PBKDF2 iterations (effectively 256,000 SHA1 operations)
 **/
@property (nonatomic, assign, readwrite) NSUInteger kdfIterNumber;

/**
 * Set the PBKDF2 iteration number for the SQLCipher database.
 *
 * In some very specific cases, it is not possible to call 'kdf_iter' (@see kdfIterNumber)
 * as one of the first operations on a database. In these cases cipherDefaultkdfIterNumber
 * can be used to globally alter the default number of PBKDF2 iterations used when opening a database.
 *
 * This is the PBKDF2 iteration number that will be passed to SQLCipher via the 'cipher_default_kdf_iter' pragma.
 * This parameter will be used everytime the database is openened and you must not change it,
 * otherwise SQLCipher will not be able to decrypt it.
 * https://www.zetetic.net/sqlcipher/sqlcipher-api/#cipher_default_kdf_iter
 *
 * You must use the 'YapDatabase/SQLCipher' subspec
 * in your Podfile for this option to take effect.
 *
 * This parameter isn't compulsory to a SQLCipher database but it is useful if you want
 * to customize the iteration count (for performance reasons) of PBKDF.
 **/
@property (nonatomic, assign, readwrite) NSUInteger cipherDefaultkdfIterNumber;

/**
 * Set the page size for the encrypted database. The default page size is 1024 bytes.
 *
 * This is the adjusted page size that will be passed to SQLCipher via the 'cipher_page_size' pragma.
 * This parameter will be used everytime the database is openened and you must not change it,
 * otherwise SQLCipher will not be able to decrypt it.
 * https://www.zetetic.net/sqlcipher/sqlcipher-api/#cipher_page_size
 *
 * You must use the 'YapDatabase/SQLCipher' subspec
 * in your Podfile for this option to take effect.
 *
 * This parameter isn't compulsory to a SQLCipher database but it is useful if you want
 * to customize the page size of your encrypted database.
 **/
@property (nonatomic, assign, readwrite) NSUInteger cipherPageSize;
#endif

/**
 * There are a few edge-case scenarios where the sqlite WAL (write-ahead log) file
 * could grow without bound, because the normal checkpoint mechanisms are getting spoiled.
 * 
 * 1. The application only does a single large write at app launch.
 *    And afterwards, it only uses the database for reads.
 *    This may be due to a bug in sqlite. Generally, once the WAL has been fully checkpointed,
 *    the next write transaction will automatically reset the WAL. But we've noticed
 *    that if the next write occurs after restarting the process, then the WAL doesn't get reset.
 * 
 * 2. The application continually writes to the database without pause.
 *    The checkpoint operation can run in parallel with reads & writes.
 *    Normally this is optimal, as the last write (in a sequence) will conclude, followed by a checkpoint.
 *    And then the next write will reset the WAL.
 *    But if the application never ceases executing write operations,
 *    then we have no choice but to occasionally interrupt the writes in order to
 *    allow the checkpoint operation to catch up.
 * 
 * If the WAL file ever reaches the configured aggressiveWALTruncationSize,
 * then YapDatabase will effectively insert a checkpoint operation as a readWriteTransction.
 *
 * (This is in contrast to its normal optimized checkpoint operations, which can run in parallel with db writes.)
 * 
 * Note: The internals approximate the file size based on the number of reported frames in the WAL.
 * The approximation is generally a bit smaller than the actual file size (as reported by the file system).
 *
 * It's unlikely you'd even notice this "aggressive" checkpoint operation,
 * unless you were benchmarking or stress testing your database system.
 * In which case you may notice this aggressive checkpoint as something of a "stutter" in the system.
 *
 * The default value is (1024 * 1024 * 4) (i.e. 4 MB)
 * 
 * Remember: This value is specified as a number of bytes. For example:
 * -   1 KB == 1024 * 1
 * - 512 KB == 1024 * 512
 * -   1 MB == 1024 * 1024
 * -  10 MB == 1024 * 1024 * 10
 *
**/
@property (nonatomic, assign, readwrite) unsigned long long aggressiveWALTruncationSize;

/**
 * This option enables multiprocess access to the database.
 *
 * All read and write operations will continue to function as expected when multiple processes are
 * concurrently accessing the database, but some optimizations are disabled when using this mode.
 *
 * For instance, when a process updates the database, all other processes must clear their cache to
 * fetch fresh data from the database.
 *
 * In the future, we might communicate changes via IPC accross processes, and it might still be possible
 * to retain most of the cache in each process.
 *
 * If you want to be notified when another process has updated the database (for instance to reload a view),
 * you can add a `CrossProcessNotifier` extension to the database and receive a
 * `YapDatabaseModifiedExternallyNotification` notification.
 *
 * WARNING: if you are using multiple processes with the same database, all processes MUST register the
 * same database extensions, otherwise unspecified behavior will happen with the creation and removal of
 * extension tables depending on when each process was started.
 *
**/
@property (nonatomic, assign, readwrite) BOOL enableMultiProcessSupport;

@end

NS_ASSUME_NONNULL_END
