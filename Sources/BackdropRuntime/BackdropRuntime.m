#import "BackdropRuntime.h"
#import <math.h>
#import <objc/runtime.h>

static char ExpectedFiltersKey;

static BOOL SameFilterChain(NSArray *actual, NSArray *expected) {
    if (!expected || actual.count != expected.count) return NO;
    for (NSUInteger i = 0; i < expected.count; ++i) {
        if (actual[i] != expected[i]) return NO;
    }
    return YES;
}

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"BackdropRuntimeUnavailable" reason:message userInfo:nil];
    }
}

static void Report(NSException *exception, NSString **reason) {
    if (reason) *reason = [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason];
}

// `filterWithType:` returns an object for any name: only `filterTypes` tells a known filter.
static id MakeFilter(Class filterType, NSString *kind) {
    if ([kind isEqualToString:@"luminanceCurveMap"]) {
        SEL types = NSSelectorFromString(@"filterTypes");
        Require([filterType respondsToSelector:types], @"CAFilter.filterTypes unavailable");
        NSMethodSignature *signature = [filterType methodSignatureForSelector:types];
        Require(signature && signature.numberOfArguments == 2 &&
                signature.methodReturnType[0] == '@', @"CAFilter.filterTypes signature changed");

        NSInvocation *query = [NSInvocation invocationWithMethodSignature:signature];
        query.target = filterType;
        query.selector = types;
        [query invoke];
        __unsafe_unretained id returnedTypes = nil;
        [query getReturnValue:&returnedTypes];
        id known = returnedTypes;
        Require([known isKindOfClass:[NSArray class]] && [known containsObject:kind],
                @"CAFilter does not know luminanceCurveMap");
    }
    SEL factory = NSSelectorFromString(@"filterWithType:");
    Require([filterType respondsToSelector:factory], @"CAFilter.filterWithType: unavailable");
    NSMethodSignature *signature = [filterType methodSignatureForSelector:factory];
    Require(signature && signature.numberOfArguments == 3 &&
            signature.methodReturnType[0] == '@' && [signature getArgumentTypeAtIndex:2][0] == '@',
            @"CAFilter factory signature changed");
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = filterType;
    invocation.selector = factory;
    [invocation setArgument:&kind atIndex:2];
    [invocation invoke];
    __unsafe_unretained id returned = nil;
    [invocation getReturnValue:&returned];
    id filter = returned;
    Require(filter != nil, [@"CAFilter rejected " stringByAppendingString:kind]);
    return filter;
}

CALayer *KOCreateBackdrop(const float *values, size_t count, const double *curve, size_t curveCount,
                          CGRect bounds, CGFloat contentsScale, NSString **reason) {
    @try {
        Require([NSThread isMainThread], @"Backdrop setup requires the main thread");
        Require(values != NULL && count == 20, @"A color matrix must have 20 floats");
        Require(curve ? curveCount == 4 : curveCount == 0,
                @"A luminance curve requires four controls, or NULL and zero");
        for (size_t i = 0; i < curveCount; ++i) {
            Require(isfinite(curve[i]) && curve[i] >= 0.0 && curve[i] <= 1.0,
                    @"Luminance curve controls must be finite and in 0...1");
        }
        Class backdropType = NSClassFromString(@"CABackdropLayer");
        Class filterType = NSClassFromString(@"CAFilter");
        Require(backdropType && [backdropType isSubclassOfClass:[CALayer class]], @"CABackdropLayer unavailable");
        Require(filterType != Nil, @"CAFilter unavailable");
        id filter = MakeFilter(filterType, @"colorMatrix");
        NSValue *matrix = [NSValue valueWithBytes:values objCType:"{CAColorMatrix=ffffffffffffffffffff}"];
        [filter setValue:matrix forKey:@"inputColorMatrix"];
        Require([[filter valueForKey:@"inputColorMatrix"] isEqual:matrix], @"Color matrix readback differs");
        NSMutableArray *filters = [NSMutableArray arrayWithObject:filter];
        if (curve != NULL) {
            // The matrix leaves the same grey on the three channels and alpha 1: the curve reads
            // that grey as luma and clamps its own output.
            id shape = MakeFilter(filterType, @"luminanceCurveMap");
            NSArray<NSNumber *> *controls = @[@(curve[0]), @(curve[1]), @(curve[2]), @(curve[3])];
            [shape setValue:controls forKey:@"inputValues"];
            [shape setValue:@1.0 forKey:@"inputAmount"];
            Require([[shape valueForKey:@"inputValues"] isEqual:controls], @"Luminance curve readback differs");
            Require([[shape valueForKey:@"inputAmount"] isEqual:@1.0], @"Luminance curve amount readback differs");
            [filters addObject:shape];
        }

        CALayer *layer = [backdropType layer];
        Require(layer != nil, @"CABackdropLayer allocation failed");
        NSDictionary<NSString *, id> *settings = @{
            @"windowServerAware": @YES, @"enabled": @YES,
            @"scale": @1.0, @"groupName": NSUUID.UUID.UUIDString
        };
        for (NSString *key in [settings.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSString *setter = [NSString stringWithFormat:@"set%@%@:",
                                [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
            Require([layer respondsToSelector:NSSelectorFromString(setter)],
                    [@"CABackdropLayer missing setter: " stringByAppendingString:setter]);
            [layer setValue:settings[key] forKey:key];
            Require([[layer valueForKey:key] isEqual:settings[key]],
                    [@"CABackdropLayer readback differs: " stringByAppendingString:key]);
        }
        layer.frame = bounds;
        layer.contentsScale = contentsScale;
        layer.masksToBounds = YES;
        NSArray *expected = [filters copy];
        layer.filters = expected;
        Require(SameFilterChain(layer.filters, expected), @"Backdrop did not retain its filters");
        objc_setAssociatedObject(layer, &ExpectedFiltersKey, expected, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return layer;
    } @catch (NSException *exception) {
        Report(exception, reason);
        return nil;
    }
}

BOOL KOAttachBackdrop(CALayer *root, CALayer *backdrop, NSString **reason) {
    @try {
        [root addSublayer:backdrop];
        Require(backdrop.superlayer == root, @"Backdrop attachment failed");
        [CATransaction flush];
        return YES;
    } @catch (NSException *exception) {
        Report(exception, reason);
        return NO;
    }
}

BOOL KOFlushBackdrop(NSString **reason) {
    @try {
        [CATransaction flush];
        return YES;
    } @catch (NSException *exception) {
        Report(exception, reason);
        return NO;
    }
}

BOOL KORecommitBackdrop(CALayer *backdrop, NSString **reason) {
    @try {
        NSArray *expected = objc_getAssociatedObject(backdrop, &ExpectedFiltersKey);
        Require(SameFilterChain(backdrop.filters, expected), @"Backdrop lost or reordered its filters");
        backdrop.filters = [expected mutableCopy];
        Require(SameFilterChain(backdrop.filters, expected), @"Backdrop rejected its filters");
        [CATransaction flush];
        return YES;
    } @catch (NSException *exception) {
        Report(exception, reason);
        return NO;
    }
}

BOOL KODetachBackdrop(CALayer *backdrop, NSString **reason) {
    @try {
        [backdrop removeFromSuperlayer];
        return YES;
    } @catch (NSException *exception) {
        Report(exception, reason);
        return NO;
    }
}
