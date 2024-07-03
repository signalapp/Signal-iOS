//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "UIButton+DeprecationWorkaround.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation UIButton (DeprecationWorkaround)

- (BOOL)ows_adjustsImageWhenDisabled
{
    return self.adjustsImageWhenDisabled;
}

- (void)ows_setAdjustsImageWhenDisabled:(BOOL)adjustsImageWhenDisabled
{
    self.adjustsImageWhenDisabled = adjustsImageWhenDisabled;
}

- (BOOL)ows_adjustsImageWhenHighlighted
{
    return self.adjustsImageWhenHighlighted;
}

- (void)ows_setAdjustsImageWhenHighlighted:(BOOL)adjustsImageWhenHighlighted
{
    self.adjustsImageWhenHighlighted = adjustsImageWhenHighlighted;
}

- (UIEdgeInsets)ows_contentEdgeInsets
{
    return self.contentEdgeInsets;
}

- (void)ows_setContentEdgeInsets:(UIEdgeInsets)contentEdgeInsets
{
    self.contentEdgeInsets = contentEdgeInsets;
}

- (UIEdgeInsets)ows_imageEdgeInsets
{
    return self.imageEdgeInsets;
}

- (void)ows_setImageEdgeInsets:(UIEdgeInsets)imageEdgeInsets
{
    self.imageEdgeInsets = imageEdgeInsets;
}

- (UIEdgeInsets)ows_titleEdgeInsets
{
    return self.titleEdgeInsets;
}

- (void)ows_setTitleEdgeInsets:(UIEdgeInsets)titleEdgeInsets
{
    self.titleEdgeInsets = titleEdgeInsets;
}

@end

#pragma clang diagnostic pop
