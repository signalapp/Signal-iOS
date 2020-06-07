//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/SDSDatabaseStorage+Objc.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

void __SDSTransactableWrite(
    SDSTransactable *transactable, SDSWriteBlock _block, NSString *_file, NSString *_function, uint32_t _line)
{
    [transactable __private_objc_writeWithFile:_file function:_function line:_line block:_block];
}

void __SDSTransactableAsyncWrite(
    SDSTransactable *transactable, SDSWriteBlock _block, NSString *_file, NSString *_function, uint32_t _line)
{
    [transactable __private_objc_asyncWriteWithFile:_file function:_function line:_line block:_block];
}

void __SDSTransactableAsyncWriteWithCompletion(SDSTransactable *transactable,
    SDSWriteBlock _block,
    SDSWriteCompletion _completion,
    NSString *_file,
    NSString *_function,
    uint32_t _line)
{
    [transactable __private_objc_asyncWriteWithFile:_file
                                           function:_function
                                               line:_line
                                              block:_block
                                         completion:_completion];
}

#pragma clang diagnostic pop
