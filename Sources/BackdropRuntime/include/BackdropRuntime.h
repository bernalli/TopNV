#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN
// Call on the main thread. Failures are strings, not Swift-imported NSError throws.
// `curve` is NULL, or the 4 control values of a `luminanceCurveMap` applied after the matrix.
CALayer * _Nullable KOCreateBackdrop(const float *values, size_t count,
                                     const double * _Nullable curve, size_t curveCount, CGRect bounds,
                                     CGFloat contentsScale, NSString * _Nullable * _Nullable reason);
BOOL KOAttachBackdrop(CALayer *root, CALayer *backdrop, NSString * _Nullable * _Nullable reason);
BOOL KOFlushBackdrop(NSString * _Nullable * _Nullable reason);
BOOL KORecommitBackdrop(CALayer *backdrop, NSString * _Nullable * _Nullable reason);
BOOL KODetachBackdrop(CALayer *backdrop, NSString * _Nullable * _Nullable reason);
NS_ASSUME_NONNULL_END
