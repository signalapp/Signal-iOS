//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// TODO: We'll eventually want to promote these into an OWSMath.h header.
static inline CGFloat CGFloatClamp(CGFloat value, CGFloat minValue, CGFloat maxValue)
{
    return MAX(minValue, MIN(maxValue, value));
}

static inline CGFloat CGFloatClamp01(CGFloat value)
{
    return CGFloatClamp(value, 0.f, 1.f);
}

static inline CGFloat CGFloatLerp(CGFloat left, CGFloat right, CGFloat alpha)
{
    alpha = CGFloatClamp01(alpha);

    return (left * (1.f - alpha)) + (right * alpha);
}

static inline CGFloat CGFloatInverseLerp(CGFloat value, CGFloat minValue, CGFloat maxValue)
{
    return (value - minValue) / (maxValue - minValue);
}

// Ceil to an even number
static inline CGFloat CeilEven(CGFloat value)
{
    return 2.f * (CGFloat)ceil(value * 0.5f);
}

NS_ASSUME_NONNULL_END
