//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSNavigationControllerBase.h"

NS_ASSUME_NONNULL_BEGIN

@interface UINavigationController (OWSNavigationControllerBase) <UINavigationBarDelegate>

@end

@implementation OWSNavigationControllerBase

- (BOOL)ows_navigationBar:(UINavigationBar *)navigationBar shouldPopItem:(UINavigationItem *)item
{
    return [super navigationBar:navigationBar shouldPopItem:item];
}

@end

NS_ASSUME_NONNULL_END
