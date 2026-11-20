#import "BackdropRuntime.h"
#import <dlfcn.h>

@protocol KOTypedFilters
+ (NSArray<NSString *> *)filterTypes;
+ (id)filterWithType:(NSString *)kind;
@end

static void Check(BOOL valid, NSString *reason) {
    if (!valid) @throw [NSException exceptionWithName:@"TwoLayerUnavailable" reason:reason userInfo:nil];
}

static id Filter(NSString *kind) {
    Class<KOTypedFilters> catalog = NSClassFromString(@"CAFilter");
    Check([[catalog filterTypes] containsObject:kind], [@"Unknown filter: " stringByAppendingString:kind]);
    id filter = [catalog filterWithType:kind];
    Check([[filter valueForKey:@"type"] isEqual:kind], [@"Filter type differs: " stringByAppendingString:kind]);
    return filter;
}

// Blend modes are exported constants. They do not appear in CAFilter.filterTypes,
// and filterWithType: alone accepts arbitrary strings.
static id LightenBlend(void) {
    CFStringRef const *symbol = dlsym(RTLD_DEFAULT, "kCAFilterLightenBlendMode");
    NSString *name = symbol ? (__bridge NSString *)*symbol : nil;
    Check([name isEqual:@"lightenBlendMode"], @"Lighten blend unavailable");
    id blend = [(Class<KOTypedFilters>)NSClassFromString(@"CAFilter") filterWithType:name];
    Check([[blend valueForKey:@"type"] isEqual:name], @"Lighten blend type differs");
    return blend;
}

static void Set(id target, NSString *key, id value) {
    [target setValue:value forKey:key];
    Check([[target valueForKey:key] isEqual:value], [@"Readback differs: " stringByAppendingString:key]);
}

static id Matrix(const float *values) {
    id filter = Filter(@"colorMatrix");
    Set(filter, @"inputColorMatrix", [NSValue valueWithBytes:values objCType:"{CAColorMatrix=ffffffffffffffffffff}"]);
    return filter;
}

static id Curve(NSArray<NSNumber *> *values) {
    id filter = Filter(@"luminanceCurveMap");
    Set(filter, @"inputAmount", @1.0);
    Set(filter, @"inputValues", values);
    return filter;
}

static void CheckGroupingAPI(CALayer *layer) {
    for (NSString *name in @[@"groupName", @"setGroupName:", @"allowsGroupBlending", @"setAllowsGroupBlending:",
                             @"allowsInPlaceFiltering", @"setAllowsInPlaceFiltering:"]) {
        Check([layer respondsToSelector:NSSelectorFromString(name)], [@"Missing selector: " stringByAppendingString:name]);
    }
}

@implementation KOTwoLayerBackdrop {
    __weak CALayer *_glyph;
    NSArray *_originalFilters, *_glyphFilters, *_pressedFilters;
    NSArray *_expectedInputs;
    NSNumber *_originalBlending, *_originalInPlace;
    BOOL _changedBlending, _changedInPlace;
    NSString *_group;
    id _blend;
}

- (NSArray *)filterInputs {
    return @[
        [_glyphFilters[0] valueForKey:@"inputColorMatrix"], [_glyphFilters[1] valueForKey:@"inputValues"],
        [_glyphFilters[1] valueForKey:@"inputAmount"], [_pressedFilters[0] valueForKey:@"inputColorMatrix"],
        [_pressedFilters[1] valueForKey:@"inputValues"], [_pressedFilters[1] valueForKey:@"inputAmount"],
        [_pressedFilters[2] valueForKey:@"inputColorMatrix"]
    ];
}

- (void)checkPair {
    CALayer *glyph = _glyph;
    Check(glyph.superlayer && _pressed.superlayer == glyph.superlayer, @"Missing sibling backdrop");
    Check([[glyph valueForKey:@"groupName"] isEqual:_group] &&
          [[_pressed valueForKey:@"groupName"] isEqual:_group], @"Shared backdrop group lost");
    for (CALayer *layer in @[glyph, _pressed]) {
        Check([[layer valueForKey:@"allowsGroupBlending"] boolValue] &&
              ![[layer valueForKey:@"allowsInPlaceFiltering"] boolValue], @"Backdrop grouping differs");
    }
    Check([glyph.filters isEqual:_glyphFilters] && [_pressed.filters isEqual:_pressedFilters], @"Filter chain differs");
    Check([[self filterInputs] isEqual:_expectedInputs], @"Filter inputs differ");
    Check([_pressed.compositingFilter isEqual:_blend], @"Lighten blend differs");
}

KOTwoLayerBackdrop *KOInstallTwoLayer(CALayer *glyph, const float glyphMatrix[20], NSArray<NSNumber *> *curve,
                                      const float threshold[20], float level, NSString **reason) {
    KOTwoLayerBackdrop *pair = [KOTwoLayerBackdrop new];
    [CATransaction begin];
    @try {
        [CATransaction setDisableActions:YES];
        Check([NSThread isMainThread] && glyph.superlayer, @"Glyph backdrop needs a parent on the main thread");
        Check(curve.count == 4 && glyph.filters.count == 1, @"Invalid glyph filter chain");
        NSString *failure = nil;
        CALayer *pressed = KOCreateBackdrop(threshold, 20, glyph.frame, glyph.contentsScale, &failure);
        Check(pressed != nil, failure ?: @"Pressed backdrop unavailable");
        CheckGroupingAPI(glyph);
        CheckGroupingAPI(pressed);
        pair->_group = [[glyph valueForKey:@"groupName"] copy];
        Check(pair->_group.length > 0, @"Missing glyph group");
        pair->_originalFilters = glyph.filters;
        pair->_originalBlending = [glyph valueForKey:@"allowsGroupBlending"];
        pair->_originalInPlace = [glyph valueForKey:@"allowsInPlaceFiltering"];
        pair->_glyphFilters = @[Matrix(glyphMatrix), Curve(curve)];
        // Explicitly saturate the threshold before scaling. Adjacent color matrices can
        // otherwise compose into one unbounded ramp. Both layers keep opaque alpha.
        const float scale[20] = {level,0,0,0,0, 0,level,0,0,0, 0,0,level,0,0, 0,0,0,0,1};
        pair->_pressedFilters = @[pressed.filters.firstObject, Curve(@[@0, @(1./3), @(2./3), @1]), Matrix(scale)];
        pair->_expectedInputs = [pair filterInputs];
        pair->_blend = LightenBlend();
        pair->_glyph = glyph;
        pair->_pressed = pressed;
        // Coincident siblings in the same group read the group's original backdrop.
        // In-place filtering would let G overwrite that input before P samples it.
        Set(pressed, @"groupName", pair->_group);
        Set(pressed, @"allowsInPlaceFiltering", @NO);
        Set(pressed, @"allowsGroupBlending", @YES);
        if (pair->_originalInPlace.boolValue) {
            pair->_changedInPlace = YES;
            Set(glyph, @"allowsInPlaceFiltering", @NO);
        }
        if (!pair->_originalBlending.boolValue) {
            pair->_changedBlending = YES;
            Set(glyph, @"allowsGroupBlending", @YES);
        }
        glyph.filters = pair->_glyphFilters;
        pressed.filters = pair->_pressedFilters;
        pressed.compositingFilter = pair->_blend;
        [glyph.superlayer insertSublayer:pressed above:glyph];
        [pair checkPair];
        return pair;
    } @catch (NSException *exception) {
        [pair remove];
        if (reason) *reason = exception.reason;
        return nil;
    } @finally {
        [CATransaction commit];
    }
}

- (BOOL)recommit:(NSString **)reason {
    @try {
        [self checkPair];
        _glyph.filters = [NSArray arrayWithArray:_glyphFilters];
        _pressed.filters = [NSArray arrayWithArray:_pressedFilters];
        [CATransaction flush];
        [self checkPair];
        return YES;
    } @catch (NSException *exception) {
        if (reason) *reason = exception.reason;
        return NO;
    }
}

- (void)remove {
    [CATransaction begin];
    @try {
        [CATransaction setDisableActions:YES];
        [_pressed removeFromSuperlayer];
        CALayer *glyph = _glyph;
        glyph.filters = _originalFilters;
        // A rejected private grouping property must not prevent single-layer fallback.
        // Once the sibling is detached, this group belongs to the glyph alone again.
        if (_changedInPlace) {
            @try { [glyph setValue:_originalInPlace forKey:@"allowsInPlaceFiltering"]; }
            @catch (NSException *unused) {}
        }
        if (_changedBlending) {
            @try { [glyph setValue:_originalBlending forKey:@"allowsGroupBlending"]; }
            @catch (NSException *unused) {}
        }
        _glyph = nil;
    } @finally {
        [CATransaction commit];
    }
}
@end
