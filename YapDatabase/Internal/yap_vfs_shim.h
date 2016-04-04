#ifndef yap_vfs_shim_h
#define yap_vfs_shim_h

#if defined __cplusplus
extern "C" {
#endif
	
#include "sqlite3.h"
#include "stdbool.h"

struct yap_vfs;
struct yap_file;

typedef struct yap_vfs yap_vfs;
typedef struct yap_file yap_file;
	
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

struct yap_vfs {
	sqlite3_vfs base;         // Base class. Must be first in struct.
	const sqlite3_vfs *pReal; // The real underlying VFS.
	
	sqlite3_mutex *last_opened_wal_mutex;
	yap_file *last_opened_wal;
};

struct yap_file {
	sqlite3_file base;             // Base class. Must be first in struct.
	const sqlite3_file *pReal;     // The real underlying file.
	
	yap_vfs *vfs;                  // Do NOT touch. For internal use only.
	yap_file *next;                // Do NOT touch. For internal use only.
	
	const char *filename;
	bool isWAL;
	
	void *yap_database_connection;
	void (*xNotifyDidRead)(yap_file*);
};

/**
 * Invoke this method to register the yap_vfs shim with the sqlite system.
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
 * @param vfs_out
 *   The allocated vfs instance.
 *   You are responsible for holding onto this pointer,
 *   and properly unregistering the shim when you're done using it.
 *
 * @return
 *   SQLITE_OK if everything went right.
 *   Some other SQLITE error if something went wrong.
**/
int yap_vfs_shim_register(const char *yap_vfs_name,         // Name for yap VFS shim
                          const char *underlying_vfs_name,  // Name of the underlying (real) VFS
                             yap_vfs **vfs_out);             // Allocated output


/**
 * Invoke this method to unregister the yap_vfs shim with the sqlite system.
 * Be sure you don't do this until you're truely done using it.
 * 
 * @param vfs
 *   The previous output from yap_vfs_shim_register.
 *   This memory will be freed within this method, and the pointer will be set to NULL.
 * 
 * @return
 *   SQLITE_OK if everything went right.
 *   Some other SQLITE error if something went wrong.
**/
int yap_vfs_shim_unregister(yap_vfs **vfs_in_out);

/**
 * SQLite doesn't seem to provide direct access to the opened sqlite3_file for the WAL.
 * This function provides the missing access, at least for the yap_vfs_shim.
 *
 * Note: SQLite opens the WAL lazily. That is, it won't open the WAL file until the first time it's needed.
 * (E.g. first transaction) So this method may return NULL until that occurs.
 * 
 * This method is thread-safe, however it's your responsibility to protect against race conditions.
 * That is, you must ensure atomicity surrounding the code that may open the wal file,
 * and the subsequent invocation of this method.
**/
yap_file* yap_vfs_last_opened_wal(yap_vfs *vfs);

#if defined __cplusplus
};
#endif

#endif /* yap_vfs_shim_h */
