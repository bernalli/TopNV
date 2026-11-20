#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN
// Call on the main thread. Failures are strings, not Swift-imported NSError throws.
CALayer * _Nullable KOCreateBackdrop(const float *values, size_t count, CGRect bounds,
                                     CGFloat contentsScale, NSString * _Nullable * _Nullable reason);
BOOL KOAttachBackdrop(CALayer *root, CALayer *backdrop, NSString * _Nullable * _Nullable reason);
BOOL KOFlushBackdrop(NSString * _Nullable * _Nullable reason);
BOOL KORecommitBackdrop(CALayer *backdrop, NSString * _Nullable * _Nullable reason);
BOOL KODetachBackdrop(CALayer *backdrop, NSString * _Nullable * _Nullable reason);
NS_ASSUME_NONNULL_END
#import "SampledBackdrop.h"
#import "TwoLayerBackdrop.h"
