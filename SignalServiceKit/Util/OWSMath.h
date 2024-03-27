//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

CG_INLINE CGFloat CGFloatClamp(CGFloat value, CGFloat minValue, CGFloat maxValue)
{
    return MAX(minValue, MIN(maxValue, value));
}

CG_INLINE CGFloat CGFloatClamp01(CGFloat value)
{
    return CGFloatClamp(value, 0.f, 1.f);
}

CG_INLINE CGFloat CGFloatLerp(CGFloat left, CGFloat right, CGFloat alpha)
{
    return (left * (1.f - alpha)) + (right * alpha);
}

CG_INLINE CGFloat CGFloatInverseLerp(CGFloat value, CGFloat minValue, CGFloat maxValue)
{
    return (value - minValue) / (maxValue - minValue);
}

// Ceil to an even number
CG_INLINE CGFloat CeilEven(CGFloat value)
{
    return 2.f * (CGFloat)ceil(value * 0.5f);
}

CG_INLINE CGSize CGSizeCeil(CGSize size)
{
    return CGSizeMake((CGFloat)ceil(size.width), (CGFloat)ceil(size.height));
}

CG_INLINE CGSize CGSizeFloor(CGSize size)
{
    return CGSizeMake((CGFloat)floor(size.width), (CGFloat)floor(size.height));
}

CG_INLINE CGSize CGSizeRound(CGSize size)
{
    return CGSizeMake((CGFloat)round(size.width), (CGFloat)round(size.height));
}

CG_INLINE CGSize CGSizeMax(CGSize size1, CGSize size2)
{
    return CGSizeMake(MAX(size1.width, size2.width), MAX(size1.height, size2.height));
}

CG_INLINE CGPoint CGPointAdd(CGPoint left, CGPoint right)
{
    return CGPointMake(left.x + right.x, left.y + right.y);
}

CG_INLINE CGPoint CGPointSubtract(CGPoint left, CGPoint right)
{
    return CGPointMake(left.x - right.x, left.y - right.y);
}

CG_INLINE CGPoint CGPointScale(CGPoint point, CGFloat factor)
{
    return CGPointMake(point.x * factor, point.y * factor);
}

CG_INLINE CGPoint CGPointMin(CGPoint left, CGPoint right)
{
    return CGPointMake(MIN(left.x, right.x), MIN(left.y, right.y));
}

CG_INLINE CGPoint CGPointMax(CGPoint left, CGPoint right)
{
    return CGPointMake(MAX(left.x, right.x), MAX(left.y, right.y));
}

CG_INLINE CGPoint CGPointClamp01(CGPoint point)
{
    return CGPointMake(CGFloatClamp01(point.x), CGFloatClamp01(point.y));
}

CG_INLINE CGPoint CGPointInvert(CGPoint point)
{
    return CGPointMake(-point.x, -point.y);
}

CG_INLINE CGSize CGSizeScale(CGSize size, CGFloat factor)
{
    return CGSizeMake(size.width * factor, size.height * factor);
}

CG_INLINE CGSize CGSizeAdd(CGSize left, CGSize right)
{
    return CGSizeMake(left.width + right.width, left.height + right.height);
}

CG_INLINE CGRect CGRectScale(CGRect rect, CGFloat factor)
{
    CGRect result;
    result.origin = CGPointScale(rect.origin, factor);
    result.size = CGSizeScale(rect.size, factor);
    return result;
}

NS_ASSUME_NONNULL_END
