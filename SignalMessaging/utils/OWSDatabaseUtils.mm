//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseUtils.h"

NS_ASSUME_NONNULL_BEGIN

extern "C" {
extern void sqlite3CodecGetKey(sqlite3 *db, int nDb, void **zKey, int *nKey);
}

NSData *_Nullable ExtractDatabaseKeySpec(sqlite3 *db)
{
    char *keySpecBytes = NULL;
    int keySpecLength = 0;
    sqlite3CodecGetKey(db, 0, (void **)&keySpecBytes, &keySpecLength);
    if (!keySpecBytes || keySpecLength < 1) {
        return nil;
    }
    NSData *_Nullable keySpecData = [NSData dataWithBytes:keySpecBytes length:(NSUInteger)keySpecLength];
    if (!keySpecData) {
        return nil;
    }

    return keySpecData;
}

NS_ASSUME_NONNULL_END
