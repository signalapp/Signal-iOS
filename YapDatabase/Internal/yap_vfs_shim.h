#ifndef yap_vfs_shim_h
#define yap_vfs_shim_h

#if defined __cplusplus
extern "C" {
#endif
	
#include "sqlite3.h"
#include "stdbool.h"

/**
 * From the SQLite Docs:
 * 
 * > From the point of view of the uppers layers of the SQLite stack, each open database file uses exactly one VFS.
 * > But in practice, a particular VFS might just be a thin wrapper around another VFS that does the real work.
 * > We call a wrapper VFS a "shim".
 * > 
 * > A simple example of a shim is the "vfstrace" VFS. This is a VFS (implemented in the test_vfstrace.c source file)
 * > that writes a message associated with each VFS method call into a log file,
 * > then passes control off to another VFS to do the actual work.
 * 
 * The yap_vfs_shim provides a "shim" around a real VFS.
 * It's designed to provide additional functionality for YapDatabaseConnection.
**/

typedef struct yap_vfs yap_vfs;
struct yap_vfs {
	sqlite3_vfs base;         // Base class. Must be first in struct.
	const sqlite3_vfs *pReal; // The real underlying VFS.
};

typedef struct yap_file yap_file;
struct yap_file {
	sqlite3_file base;             // Base class. Must be first in struct.
	const sqlite3_file *pReal;     // The real underlying file.
	
	yap_file *next;                // Do NOT touch. For internal use only.
	
	const char *filename;
	bool isWAL;
	
	void *yap_database_connection;
	void (*xNotifyDidRead)(yap_file*);
};

/**
 * Invoke this method to register the yap_vfs shim with the sqlite system.
 * 
 * Thie method only needs to be called once.
 * It is recommended you use something like dispatch_once or std::call_once to invoke it.
 * 
 * @param yap_vfs_name
 *   The name to use when registering the shim with sqlite.
 *   In order to use the shim, you pass the same name when opening a database.
 *   That is, as the last parameter to sqlite3_open_v2().
 * 
 * @param underlying_vfs_name
 *   The name of the vfs that the shim is to wrap.
 *   That is, the underlying vfs that does the actual work.
 *   You can pass NULL to specify the default vfs.
 * 
 * @return
 *   SQLITE_OK if everything went right.
 *   Some other SQLITE error if something went wrong.
**/
int yap_vfs_shim_register(const char *yap_vfs_name,         // Name for yap VFS shim
                          const char *underlying_vfs_name); // Name of the underlying VFS


/**
 * SQLite doesn't seem to provide direct access to the opened sqlite3_file for the WAL.
 * This function provides the missing access, at least for the yap_vfs_shim.
 *
 * Note: SQLite opens the WAL lazily. That is, it won't open the WAL file until the first time it's needed.
 * (E.g. first transaction) So this method may return NULL until that occurs.
 * 
 * This method is thread-safe.
**/
yap_file* yap_file_wal_find(yap_file *main_file);

#if defined __cplusplus
};
#endif

#endif /* yap_vfs_shim_h */
