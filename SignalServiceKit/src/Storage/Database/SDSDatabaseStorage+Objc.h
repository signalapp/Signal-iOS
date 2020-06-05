//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#define DatabaseStorageWrite(__databaseStorage, __block)                                                               \
    [__databaseStorage writeWithFile:[NSString stringWithUTF8String:__FILE__]                                          \
                            function:[NSString stringWithUTF8String:__PRETTY_FUNCTION__]                               \
                                line:__LINE__                                                                          \
                               block:__block];

#define DatabaseStorageAsyncWrite(__databaseStorage, __block)                                                          \
    [__databaseStorage asyncWriteWithFile:[NSString stringWithUTF8String:__FILE__]                                     \
                                 function:[NSString stringWithUTF8String:__PRETTY_FUNCTION__]                          \
                                     line:__LINE__                                                                     \
                                    block:__block];

#define DatabaseStorageAsyncWriteWithCompletion(__databaseStorage, __block, __completion)                              \
    [__databaseStorage asyncWriteWithFile:[NSString stringWithUTF8String:__FILE__]                                     \
                                 function:[NSString stringWithUTF8String:__PRETTY_FUNCTION__]                          \
                                     line:__LINE__                                                                     \
                                    block:__block                                                                      \
                               completion:__completion];
