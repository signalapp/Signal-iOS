#include "yap_vfs_shim.h"

#include <stdio.h>
#include <stddef.h>
#include <string.h>


static yap_file *yap_file_wal_linked_list = NULL;
static sqlite3_mutex *yap_file_wal_linked_list_mutex = NULL;


static bool yap_file_wal_matches(yap_file *main_file, yap_file *wal_file)
{
	// Compare main_file->filename to wal_file->filename
	//
	// The filenames should be the same,
	// except the wal filename should also have a "-wal" suffix at the end.
	//
	// E.g.
	// - main : "/foo/bar/db.sqlite"
	// - wal  : "/foo/bar/db.sqlite-wal"
	
	const char *main_filename = main_file->filename;
	const char *wal_filename = wal_file->filename;
	
	if (main_filename == NULL) return false;
	if (wal_filename  == NULL) return false;
	
	size_t main_len = strlen(main_filename);
	
	if (strncmp(main_filename, wal_filename, main_len) != 0) return false;
	
	size_t wal_len = strlen(wal_filename);
	
	const char *suffix = "-wal";
	size_t suffixLen = strlen(suffix);
	
	if (wal_len != (main_len + suffixLen)) return false;
	
	if (strncmp(wal_filename + main_len, suffix, suffixLen) != 0) return false;
	
	return wal_file->isWAL;
}

static void yap_file_wal_register(yap_file *file)
{
	if (file == NULL) return;
	
	sqlite3_mutex_enter(yap_file_wal_linked_list_mutex);
	{
		// Add to front of linked list
		
		if (yap_file_wal_linked_list)
		{
			file->next = yap_file_wal_linked_list;
		}
		
		yap_file_wal_linked_list = file;
	}
	sqlite3_mutex_leave(yap_file_wal_linked_list_mutex);
}

static void yap_file_wal_unregister(yap_file *file)
{
	if (file == NULL) return;
	
	sqlite3_mutex_enter(yap_file_wal_linked_list_mutex);
	{
		yap_file *match = NULL;
		yap_file *match_prev = NULL;
		
		yap_file *item = yap_file_wal_linked_list;
		
		while (item)
		{
			if (item == file)
			{
				match = item;
				break;
			}
			else
			{
				match_prev = item;
			}
			
			item = item->next;
		}
		
		if (match)
		{
			if (yap_file_wal_linked_list == match)
				yap_file_wal_linked_list = match->next;
			
			if (match_prev)
				match_prev->next = match->next;
		}
	}
	sqlite3_mutex_leave(yap_file_wal_linked_list_mutex);
}

/**
 * SQLite doesn't seem to provide direct access to the opened sqlite3_file for the WAL.
 * This function provides the missing access, at least for the yap_vfs_shim.
 *
 * Note: SQLite opens the WAL lazily. That is, it won't open the WAL file until the first time it's needed.
 * (E.g. first transaction) So this method may return NULL until that occurs.
**/
yap_file* yap_file_wal_find(yap_file *main_file)
{
	if (main_file == NULL) return NULL;
	
	yap_file *match = NULL;
	
	sqlite3_mutex_enter(yap_file_wal_linked_list_mutex);
	{
		yap_file *item = yap_file_wal_linked_list;
		while (item)
		{
			if (yap_file_wal_matches(main_file, item))
			{
				match = item;
				break;
			}
			
			item = item->next;
		}
	}
	sqlite3_mutex_leave(yap_file_wal_linked_list_mutex);
	
	return match;
}

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
			yap_file_wal_unregister(yapFile);
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
	yap_file *yapFile = (yap_file *)file;
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
	
	const sqlite3_vfs *realVFS = ((yap_vfs *)vfs)->pReal;
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
		yap_file_wal_register(yapFile);
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark sqlite3_vfs_shim
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

int yap_vfs_shim_register(const char *yap_vfs_name,        // Name for yap VFS shim
                          const char *underlying_vfs_name) // Name of the underlying VFS
{
	// We do this here because this method is typically only called once.
	// And is expected to be called in a thread-safe manner.
	if (yap_file_wal_linked_list_mutex == NULL) {
		yap_file_wal_linked_list_mutex = sqlite3_mutex_alloc(SQLITE_MUTEX_FAST);
	}
	
	if (yap_vfs_name == NULL)
	{
		// yap_vfs_name is required
		return SQLITE_MISUSE;
	}
	
	sqlite3_vfs *realVFS = sqlite3_vfs_find(underlying_vfs_name);
	if (realVFS == NULL) {
		return SQLITE_NOTFOUND;
	}
	
	size_t baseLen = sizeof(yap_vfs);
	size_t nameLen = strlen(yap_vfs_name) + 1;
	
	yap_vfs *yapVFS = sqlite3_malloc((int)(baseLen + nameLen));
	if (yapVFS == NULL) {
		return SQLITE_NOMEM;
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
	
	int makeDefault = 0; // NO
	int result = sqlite3_vfs_register((sqlite3_vfs *)yapVFS, makeDefault);
	if (result != SQLITE_OK)
	{
		sqlite3_free(yapVFS);
	}
	
	return result;
}
