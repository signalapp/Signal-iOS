//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// All Obj-c database storage writes should be done using these macros.
// They capture the logging info.

@class SDSAnyWriteTransaction;
@class SDSDatabaseStorage;

typedef void (^SDSWriteBlock)(SDSAnyWriteTransaction *);
typedef void (^SDSWriteCompletion)(void);

void __SDSDatabaseStorageWrite(
    SDSDatabaseStorage *databaseStorage, SDSWriteBlock _block, NSString *_file, NSString *_function, uint32_t _line);

void __SDSDatabaseStorageAsyncWrite(
    SDSDatabaseStorage *databaseStorage, SDSWriteBlock _block, NSString *_file, NSString *_function, uint32_t _line);

#define DatabaseStorageWrite(__databaseStorage, __block)                                                               \
    __SDSDatabaseStorageWrite(__databaseStorage,                                                                       \
        __block,                                                                                                       \
        [NSString stringWithUTF8String:__FILE__],                                                                      \
        [NSString stringWithUTF8String:__PRETTY_FUNCTION__],                                                           \
        __LINE__);

#define DatabaseStorageAsyncWrite(__databaseStorage, __block)                                                          \
    __SDSDatabaseStorageAsyncWrite(__databaseStorage,                                                                  \
        __block,                                                                                                       \
        [NSString stringWithUTF8String:__FILE__],                                                                      \
        [NSString stringWithUTF8String:__PRETTY_FUNCTION__],                                                           \
        __LINE__);
