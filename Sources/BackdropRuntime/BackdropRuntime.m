#import "BackdropRuntime.h"

static void Require(BOOL condition, NSString *message) {
    if (!condition) {
        @throw [NSException exceptionWithName:@"BackdropRuntimeUnavailable" reason:message userInfo:nil];
    }
}

static void Report(NSException *exception, NSString **reason) {
    if (reason) *reason = [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason];
}

CALayer *KOCreateBackdrop(const float *values, size_t count, CGRect bounds,
                          CGFloat contentsScale, NSString **reason) {
    @try {
        Require([NSThread isMainThread], @"Backdrop setup requires the main thread");
        Require(values != NULL && count == 20, @"A color matrix must have 20 floats");
        Class backdropType = NSClassFromString(@"CABackdropLayer");
        Class filterType = NSClassFromString(@"CAFilter");
        Require(backdropType && [backdropType isSubclassOfClass:[CALayer class]], @"CABackdropLayer unavailable");
        Require(filterType != Nil, @"CAFilter unavailable");
        SEL factory = NSSelectorFromString(@"filterWithType:");
        Require([filterType respondsToSelector:factory], @"CAFilter.filterWithType: unavailable");
        NSMethodSignature *signature = [filterType methodSignatureForSelector:factory];
        Require(signature && signature.numberOfArguments == 3 &&
                signature.methodReturnType[0] == '@' && [signature getArgumentTypeAtIndex:2][0] == '@',
                @"CAFilter factory signature changed");
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = filterType;
        invocation.selector = factory;
        NSString *kind = @"colorMatrix";
        [invocation setArgument:&kind atIndex:2];
        [invocation invoke];
        __unsafe_unretained id returned = nil;
        [invocation getReturnValue:&returned];
        id filter = returned;
        Require(filter != nil, @"CAFilter rejected colorMatrix");
        NSValue *matrix = [NSValue valueWithBytes:values objCType:"{CAColorMatrix=ffffffffffffffffffff}"];
        [filter setValue:matrix forKey:@"inputColorMatrix"];
        Require([[filter valueForKey:@"inputColorMatrix"] isEqual:matrix], @"Color matrix readback differs");

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
        layer.filters = @[filter];
        Require(layer.filters.count == 1 && layer.filters.firstObject == filter, @"Backdrop did not retain its filter");
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
        // A fresh array makes the assignment a real change, so the flush carries it to the render server.
        Require(backdrop.filters.count == 1, @"Backdrop lost its filter");
        backdrop.filters = [NSArray arrayWithArray:backdrop.filters];
        Require(backdrop.filters.count == 1, @"Backdrop rejected its filter");
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
