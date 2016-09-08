#include "yap_vfs_shim.h"

#include <stdio.h>
#include <stddef.h>
#include <string.h>

static void yap_vfs_set_last_opened_wal(yap_vfs *yapVFS, yap_file *yapFile);
static void yap_vfs_unset_last_opened_wal(yap_vfs *yapVFS, yap_file *yapFile);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark sqlite3_io_methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

static int yap_file_close(sqlite3_file *file)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	int result = realFile->pMethods->xClose((sqlite3_file *)realFile);
	
	if (result == SQLITE_OK)
	{
		sqlite3_free((void *)yapFile->base.pMethods);
		yapFile->base.pMethods = NULL;
		
		if (yapFile->isWAL)
		{
			yap_vfs_unset_last_opened_wal(yapFile->vfs, yapFile);
		}
	}
	
	return result;
}

static int yap_file_read(sqlite3_file *file, void *zBuf, int iAmt, sqlite3_int64 iOfst)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	int result = realFile->pMethods->xRead((sqlite3_file *)realFile, zBuf, iAmt, iOfst);
	
	if (yapFile->xNotifyDidRead && (result == SQLITE_OK))
	{
		yapFile->xNotifyDidRead(yapFile);
	}
	
	return result;
}

static int yap_file_write(sqlite3_file *file, const void *zBuf, int iAmt, sqlite3_int64 iOfst)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xWrite((sqlite3_file *)realFile, zBuf, iAmt, iOfst);
}

static int yap_file_truncate(sqlite3_file *file, sqlite3_int64 size)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xTruncate((sqlite3_file *)realFile, size);
}

static int yap_file_sync(sqlite3_file *file, int flags)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xSync((sqlite3_file *)realFile, flags);
}

static int yap_file_fileSize(sqlite3_file *file, sqlite3_int64 *pSize)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xFileSize((sqlite3_file *)realFile, pSize);
}

static int yap_file_lock(sqlite3_file *file, int eLock)
{
	yap_file * yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xLock((sqlite3_file *)realFile, eLock);
}

static int yap_file_unlock(sqlite3_file *file, int eLock)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xUnlock((sqlite3_file *)realFile, eLock);
}

static int yap_file_checkReservedLock(sqlite3_file *file, int *pResOut)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xCheckReservedLock((sqlite3_file *)realFile, pResOut);
}

static int yap_file_fileControl(sqlite3_file *file, int op, void *pArg)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xFileControl((sqlite3_file *)realFile, op, pArg);
}

static int yap_file_sectorSize(sqlite3_file *file)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xSectorSize((sqlite3_file *)realFile);
}

static int yap_file_deviceCharacteristics(sqlite3_file *file)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xDeviceCharacteristics((sqlite3_file *)realFile);
}

static int yap_file_shmMap(sqlite3_file *file, int iPg, int pgsz, int isWrite, void volatile **pp)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xShmMap((sqlite3_file *)realFile, iPg, pgsz, isWrite, pp);
}

static int yap_file_shmLock(sqlite3_file *file, int offset, int n, int flags)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xShmLock((sqlite3_file *)realFile, offset, n, flags);
}

static void yap_file_shmBarrier(sqlite3_file *file)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xShmBarrier((sqlite3_file *)realFile);
}

static int yap_file_shmUnmap(sqlite3_file *file, int deleteFlag)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	return realFile->pMethods->xShmUnmap((sqlite3_file *)realFile, deleteFlag);
}

static int yap_file_fetch(sqlite3_file *file, sqlite3_int64 iOfst, int iAmt, void **pp)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
	int result = realFile->pMethods->xFetch((sqlite3_file *)realFile, iOfst, iAmt, pp);
	
	// Note: fetch is read for memory mapped IO
	
	if (yapFile->xNotifyDidRead && (result == SQLITE_OK))
	{
		yapFile->xNotifyDidRead(yapFile);
	}
	
	return result;
}

static int yap_file_unfetch(sqlite3_file *file, sqlite3_int64 iOfst, void *ptr)
{
	yap_file *yapFile = (yap_file *)file;
	const sqlite3_file *realFile = yapFile->pReal;
	
//	printf("%s: unfetch\n", (yapFile->isWAL ? "WAL" : "main"));
	
	return realFile->pMethods->xUnfetch((sqlite3_file *)realFile, iOfst, ptr);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark sqlite3_vfs methods
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

static int yap_vfs_open(sqlite3_vfs *vfs, const char *zName, sqlite3_file *file, int flags, int *pOutFlags)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	yap_file *yapFile = (yap_file *)file;
	
	yapFile->vfs = yapVFS;
	yapFile->next = NULL;
	
	// Regarding zName parameter, from the SQLite docs:
	//
	// > SQLite guarantees that the zName string will be valid and unchanged until xClose() is called.
	// > Because of this, the sqlite3_file can safely store a pointer to the filename if it needs to
	// > remember the filename for some reason.
	
	yapFile->filename = zName;
	yapFile->isWAL = (flags & SQLITE_OPEN_WAL) ? true : false;
	
	// yapFile memory = {struct yap_file, byte[realVFS->szOsFile]}
	
	sqlite3_file *realFile = (sqlite3_file *)&yapFile[1];
	yapFile->pReal = realFile;
	
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	int result = realVFS->xOpen((sqlite3_vfs *)realVFS, zName, realFile, flags, pOutFlags);
	
	if (realFile->pMethods)
	{
		sqlite3_io_methods *yapMethods = sqlite3_malloc(sizeof(sqlite3_io_methods));
		if (yapMethods == NULL) {
			return SQLITE_NOMEM;
		}
		memset(yapMethods, 0, sizeof(sqlite3_io_methods));
		
		const sqlite3_io_methods *realMethods = realFile->pMethods;
		
		yapMethods->iVersion               = realMethods->iVersion;
		yapMethods->xClose                 = yap_file_close;
		yapMethods->xRead                  = yap_file_read;
		yapMethods->xWrite                 = yap_file_write;
		yapMethods->xTruncate              = yap_file_truncate;
		yapMethods->xSync                  = yap_file_sync;
		yapMethods->xFileSize              = yap_file_fileSize;
		yapMethods->xLock                  = yap_file_lock;
		yapMethods->xUnlock                = yap_file_unlock;
		yapMethods->xCheckReservedLock     = yap_file_checkReservedLock;
		yapMethods->xFileControl           = yap_file_fileControl;
		yapMethods->xSectorSize            = yap_file_sectorSize;
		yapMethods->xDeviceCharacteristics = yap_file_deviceCharacteristics;
		
		if (realMethods->iVersion >= 2)
		{
			yapMethods->xShmMap     = realMethods->xShmMap     ? yap_file_shmMap     : NULL;
			yapMethods->xShmLock    = realMethods->xShmLock    ? yap_file_shmLock    : NULL;
			yapMethods->xShmBarrier = realMethods->xShmBarrier ? yap_file_shmBarrier : NULL;
			yapMethods->xShmUnmap   = realMethods->xShmUnmap   ? yap_file_shmUnmap   : NULL;
			
			if (realMethods->iVersion >= 3)
			{
				yapMethods->xFetch   = realMethods->xFetch   ? yap_file_fetch   : NULL;
				yapMethods->xUnfetch = realMethods->xUnfetch ? yap_file_unfetch : NULL;
			}
		}
		
		yapFile->base.pMethods = yapMethods;
	}
	
	if (result == SQLITE_OK && yapFile->isWAL)
	{
		yap_vfs_set_last_opened_wal(yapFile->vfs, yapFile);
	}
	
	return result;
}

static int yap_vfs_delete(sqlite3_vfs *vfs, const char *zName, int syncDir)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	return realVFS->xDelete((sqlite3_vfs *)realVFS, zName, syncDir);
}

static int yap_vfs_access(sqlite3_vfs *vfs, const char *zName, int flags, int *pResOut)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	return realVFS->xAccess((sqlite3_vfs *)realVFS, zName, flags, pResOut);
}

static int yap_vfs_fullPathname(sqlite3_vfs *vfs, const char *zName, int nOut, char *zOut)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	return realVFS->xFullPathname((sqlite3_vfs *)realVFS, zName, nOut, zOut);
}

static void* yap_vfs_dlOpen(sqlite3_vfs *vfs, const char *zFilename)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	return realVFS->xDlOpen((sqlite3_vfs *)realVFS, zFilename);
}

void yap_vfs_dlError(sqlite3_vfs *vfs, int nByte, char *zErrMsg)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	realVFS->xDlError((sqlite3_vfs *)realVFS, nByte, zErrMsg);
}

static void (*yap_vfs_dlSym(sqlite3_vfs *vfs, void *ptr, const char *zSym))(void)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	return realVFS->xDlSym((sqlite3_vfs *)realVFS, ptr, zSym);
}

static void yap_vfs_dlClose(sqlite3_vfs *vfs, void *ptr)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	realVFS->xDlClose((sqlite3_vfs *)realVFS, ptr);
}

static int yap_vfs_randomness(sqlite3_vfs *vfs, int nByte, char *zOut)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	return realVFS->xRandomness((sqlite3_vfs *)realVFS, nByte, zOut);
}

static int yap_vfs_sleep(sqlite3_vfs *vfs, int microseconds)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	return realVFS->xSleep((sqlite3_vfs *)realVFS, microseconds);
}

static int yap_vfs_currentTime(sqlite3_vfs *vfs, double *pTimeOut)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	return realVFS->xCurrentTime((sqlite3_vfs *)realVFS, pTimeOut);
}

static int yap_vfs_getLastError(sqlite3_vfs *vfs, int iErr, char *zErr)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	return realVFS->xGetLastError((sqlite3_vfs *)realVFS, iErr, zErr);
}

static int yap_vfs_currentTimeInt64(sqlite3_vfs *vfs, sqlite3_int64 *pTimeOut)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	return realVFS->xCurrentTimeInt64((sqlite3_vfs *)realVFS, pTimeOut);
}

static int yap_vfs_setSystemCall(sqlite3_vfs *vfs, const char *zName, sqlite3_syscall_ptr pFunc)
{
	const sqlite3_vfs *p = ((yap_vfs *)vfs)->pReal;
	return p->xSetSystemCall((sqlite3_vfs *)p, zName, pFunc);
}

static sqlite3_syscall_ptr yap_vfs_getSystemCall(sqlite3_vfs *vfs, const char *zName)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	return realVFS->xGetSystemCall((sqlite3_vfs *)realVFS, zName);
}

static const char* yap_vfs_nextSystemCall(sqlite3_vfs *vfs, const char *zName)
{
	yap_vfs *yapVFS = (yap_vfs *)vfs;
	const sqlite3_vfs *realVFS = yapVFS->pReal;
	
	return realVFS->xNextSystemCall((sqlite3_vfs *)realVFS, zName);
}

static void yap_vfs_set_last_opened_wal(yap_vfs *yapVFS, yap_file *yapFile)
{
	if (yapVFS == NULL) return;
	
	sqlite3_mutex_enter(yapVFS->last_opened_wal_mutex);
	{
		yapVFS->last_opened_wal = yapFile;
	}
	sqlite3_mutex_leave(yapVFS->last_opened_wal_mutex);
}

static void yap_vfs_unset_last_opened_wal(yap_vfs *yapVFS, yap_file *yapFile)
{
	if (yapVFS == NULL) return;
	
	sqlite3_mutex_enter(yapVFS->last_opened_wal_mutex);
	{
		if (yapVFS->last_opened_wal == yapFile) {
			yapVFS->last_opened_wal = NULL;
		}
	}
	sqlite3_mutex_leave(yapVFS->last_opened_wal_mutex);
}

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
yap_file* yap_vfs_last_opened_wal(yap_vfs *yapVFS)
{
	if (yapVFS == NULL) return NULL;
	
	yap_file *last_opened_wal = NULL;
	
	sqlite3_mutex_enter(yapVFS->last_opened_wal_mutex);
	{
		last_opened_wal = yapVFS->last_opened_wal;
	}
	sqlite3_mutex_leave(yapVFS->last_opened_wal_mutex);
	
	return last_opened_wal;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark sqlite3_vfs_shim
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
int yap_vfs_shim_register(const char *yap_vfs_name,        // Name for yap VFS shim
                          const char *underlying_vfs_name, // Name of the underlying (real) VFS
                             yap_vfs **vfs_out)            // Allocated output
{
	int result = SQLITE_OK;
	yap_vfs *yapVFS = NULL;
	
	if (yap_vfs_name == NULL)
	{
		// yap_vfs_name is required
		result = SQLITE_MISUSE;
		goto done;
	}
	
	sqlite3_vfs *realVFS = sqlite3_vfs_find(underlying_vfs_name);
	if (realVFS == NULL)
	{
		result = SQLITE_NOTFOUND;
		goto done;
	}
	
	size_t baseLen = sizeof(yap_vfs);
	size_t nameLen = strlen(yap_vfs_name) + 1;
	
	yapVFS = sqlite3_malloc((int)(baseLen + nameLen));
	if (yapVFS == NULL)
	{
		result = SQLITE_NOMEM;
		goto done;
	}
	memset(yapVFS, 0, (int)(baseLen + nameLen));
	
	// yapVFS memory = {struct yap_vfs, char[nameLen]}
	
	char *name = (char *)&yapVFS[1];
	strncpy(name, yap_vfs_name, nameLen);
	
	yapVFS->base.iVersion   = realVFS->iVersion;
	yapVFS->base.szOsFile   = sizeof(yap_file) + realVFS->szOsFile;
	yapVFS->base.mxPathname = realVFS->mxPathname;
	yapVFS->base.zName      = name;
	
	yapVFS->base.xOpen         = yap_vfs_open;
	yapVFS->base.xDelete       = yap_vfs_delete;
	yapVFS->base.xAccess       = yap_vfs_access;
	yapVFS->base.xFullPathname = yap_vfs_fullPathname;
	yapVFS->base.xDlOpen       = realVFS->xDlOpen  ? yap_vfs_dlOpen  : NULL;
	yapVFS->base.xDlError      = realVFS->xDlError ? yap_vfs_dlError : NULL;
	yapVFS->base.xDlSym        = realVFS->xDlSym   ? yap_vfs_dlSym   : NULL;
	yapVFS->base.xDlClose      = realVFS->xDlClose ? yap_vfs_dlClose : NULL;
	yapVFS->base.xRandomness   = yap_vfs_randomness;
	yapVFS->base.xSleep        = yap_vfs_sleep;
	yapVFS->base.xCurrentTime  = yap_vfs_currentTime;
	yapVFS->base.xGetLastError = realVFS->xGetLastError ? yap_vfs_getLastError : NULL;
	
	if (realVFS->iVersion >= 2)
	{
		yapVFS->base.xCurrentTimeInt64 = realVFS->xCurrentTimeInt64 ? yap_vfs_currentTimeInt64 : NULL;
		
		if (realVFS->iVersion >= 3)
		{
			yapVFS->base.xSetSystemCall  = realVFS->xSetSystemCall  ? yap_vfs_setSystemCall  : NULL;
			yapVFS->base.xGetSystemCall  = realVFS->xGetSystemCall  ? yap_vfs_getSystemCall  : NULL;
			yapVFS->base.xNextSystemCall = realVFS->xNextSystemCall ? yap_vfs_nextSystemCall : NULL;
		}
	}
	
	yapVFS->pReal = realVFS;
	yapVFS->last_opened_wal_mutex = sqlite3_mutex_alloc(SQLITE_MUTEX_FAST);
	
	int makeDefault = 0; // NO
	result = sqlite3_vfs_register((sqlite3_vfs *)yapVFS, makeDefault);
	
done:
	
	if (result != SQLITE_OK)
	{
		if (yapVFS) {
			sqlite3_free(yapVFS);
		}
	}
	
	*vfs_out = yapVFS;
	return result;
}

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
int yap_vfs_shim_unregister(yap_vfs **vfs_in_out)
{
	if (vfs_in_out == NULL) {
		return SQLITE_MISUSE;
	}
	
	yap_vfs *yapVFS = *vfs_in_out;
	
	if (yapVFS == NULL) {
		return SQLITE_MISUSE;
	}
	
	if (yapVFS->last_opened_wal_mutex) {
		sqlite3_mutex_free(yapVFS->last_opened_wal_mutex);
		yapVFS->last_opened_wal_mutex = NULL;
	}
	
	int result = sqlite3_vfs_unregister((sqlite3_vfs *)yapVFS);
	
	sqlite3_free(yapVFS);
	*vfs_in_out = NULL;
	
	return result;
}
