//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// TODO: We'll eventually want to promote these into an OWSMath.h header.
static inline CGFloat Clamp(CGFloat value, CGFloat minValue, CGFloat maxValue)
{
    return MAX(minValue, MIN(maxValue, value));
}

static inline CGFloat Clamp01(CGFloat value)
{
    return Clamp(value, 0.f, 1.f);
}

static inline CGFloat CGFloatLerp(CGFloat left, CGFloat right, CGFloat alpha)
{
    alpha = Clamp01(alpha);

    return (left * (1.f - alpha)) + (right * alpha);
}

static inline CGFloat CGFloatInverseLerp(CGFloat value, CGFloat minValue, CGFloat maxValue)
{
    return (value - minValue) / (maxValue - minValue);
}

NS_ASSUME_NONNULL_END
