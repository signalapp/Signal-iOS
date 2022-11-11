//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "SDSDatabaseStorage+Objc.h"
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

#pragma clang diagnostic pop
