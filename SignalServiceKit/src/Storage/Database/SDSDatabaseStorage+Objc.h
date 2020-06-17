//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

// All Obj-c database storage writes should be done using these macros.
// They capture the logging info.

@class SDSAnyWriteTransaction;
@class SDSTransactable;

typedef void (^SDSWriteBlock)(SDSAnyWriteTransaction *);
typedef void (^SDSWriteCompletion)(void);

void __SDSTransactableWrite(
    SDSTransactable *transactable, SDSWriteBlock _block, NSString *_file, NSString *_function, uint32_t _line);

void __SDSTransactableAsyncWrite(
    SDSTransactable *transactable, SDSWriteBlock _block, NSString *_file, NSString *_function, uint32_t _line);

#define DatabaseStorageWrite(__databaseStorage, __block)                                                               \
    __SDSTransactableWrite(__databaseStorage,                                                                          \
        __block,                                                                                                       \
        [NSString stringWithUTF8String:__FILE__],                                                                      \
        [NSString stringWithUTF8String:__PRETTY_FUNCTION__],                                                           \
        __LINE__);

#define DatabaseStorageAsyncWrite(__databaseStorage, __block)                                                          \
    __SDSTransactableAsyncWrite(__databaseStorage,                                                                     \
        __block,                                                                                                       \
        [NSString stringWithUTF8String:__FILE__],                                                                      \
        [NSString stringWithUTF8String:__PRETTY_FUNCTION__],                                                           \
        __LINE__);
