# OpenSim Plan 0 — Private API Feasibility Spike

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Xác minh trên Xcode 27.1 rằng OpenSim có thể render màn hình simulator, inject tap/type, đọc accessibility tree, và render watchOS/tvOS; nếu không, chốt fallback kèm chi phí trước khi viết Plan 1.

**Architecture:** Một probe Objective-C throwaway, chạy ngoài app, `dlopen` CoreSimulator và SimulatorKit, dùng Objective-C runtime để tìm class/selector, dựng cửa sổ AppKit chứa `SimulatorKit.SimDisplayView`, và dùng `simctl` để kiểm chứng ảnh. Không viết production code trong plan này.

**Tech Stack:** macOS 27.0.1, Xcode 27.1, Objective-C + AppKit, CoreSimulator/SimulatorKit private frameworks, `simctl`, ImageIO/IOSurface.

**Spec:** `docs/superpowers/specs/2026-10-19-open-simulator-design.md`

## Global Constraints

- macOS 27.0+; Xcode 27.1+; arm64.
- Spike code nằm trong `spike/` và **không commit**; `spike/` đã có trong `.gitignore`.
- Không sửa source production; chưa có source production trong repo.
- Không tự ý tải watchOS/tvOS runtime; cần owner đồng ý trước khi chạy `xcodebuild -downloadPlatform`.
- Không xoá device hiện có; chỉ tạo/xoá device có tên bắt đầu bằng `OpenSim Spike`.
- Dùng device iPhone Air đang boot nếu có; nếu không, chạy `xcrun simctl boot "iPhone Air"` và chờ 5 giây trước mọi check.
- Timebox toàn bộ spike: 90 phút. Gặp blocker thì ghi lại và dừng, không suy diễn.
- Report và plan viết bằng tiếng Việt; code/comment tiếng Anh; không dùng ký tự CJK.
- Chỉ commit plan, report, artifact ảnh; không commit `spike/`.
- Không dùng Chrome hoặc công cụ ngoài Apple cho spike.

---

## File Structure

| File | Trách nhiệm | Commit? |
|---|---|---|
| `spike/probe.m` | Probe ObjC: load framework, introspect, device, render, input, a11y | Không |
| `spike/run.sh` | Compile và chạy probe | Không |
| `spike/check-inspect.sh` | Check class/selector introspection | Không |
| `spike/check-devices.sh` | Check truy cập CoreSimulator device | Không |
| `spike/check-render.sh` | Check render + chụp cửa sổ | Không |
| `spike/check-input.sh` | Check tap/type bằng screenshot hash | Không |
| `spike/check-a11y.sh` | Check kết quả accessibility | Không |
| `spike/check-platforms.sh` | Check watchOS/tvOS runtime availability | Không |
| `spike/out/` | Output/log/ảnh tạm | Không |
| `docs/superpowers/spikes/2026-10-19-private-api-spike.md` | Report quyết định | Có |
| `docs/superpowers/spikes/artifacts/` | Ảnh bằng chứng | Có |
| `docs/superpowers/plans/2026-10-19-opensim-plan-0-private-api-spike.md` | Plan này | Có |

---

### Task 1: Probe scaffold và introspection

**Files:**
- Create: `spike/probe.m`
- Create: `spike/run.sh`
- Create: `spike/check-inspect.sh`

**Interfaces:**
- Produces: `probe inspect` in danh sách `CLASS <name>` và method/property ObjC-visible.
- Produces: `run.sh <mode> [args]` dùng cho mọi task sau.

- [ ] **Step 1: Viết check thất bại**

Create `spike/check-inspect.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
OUT="$("$ROOT/spike/run.sh" inspect 2>&1)"
print -r -- "$OUT" > "$ROOT/spike/out/inspect.txt"
for cls in SimServiceContext SimDeviceSet SimDevice SimulatorKit.SimDisplayView; do
  if ! print -r -- "$OUT" | grep -q "CLASS $cls"; then
    print -u2 "MISSING $cls"
    exit 1
  fi
done
print "OK inspect"
```

- [ ] **Step 2: Chạy check để thấy fail**

Run:

```bash
chmod +x spike/check-inspect.sh
./spike/check-inspect.sh
```

Expected: FAIL vì `spike/run.sh` hoặc `spike/probe.m` chưa tồn tại.

- [ ] **Step 3: Viết probe scaffold**

Create `spike/probe.m`:

```objc
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSString *xcodeDeveloperDir(void) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/xcode-select";
    task.arguments = @[@"-p"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    [task launch];
    [task waitUntilExit];
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString *path = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [path stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *simulatorKitPath(void) {
    NSString *developer = xcodeDeveloperDir();
    NSString *contents = [developer stringByDeletingLastPathComponent];
    return [contents stringByAppendingPathComponent:@"SharedFrameworks/SimulatorKit.framework/Versions/A/SimulatorKit"];
}

static BOOL loadFramework(NSString *path) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        fprintf(stderr, "missing: %s\n", path.UTF8String);
        return NO;
    }
    if (!dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL)) {
        fprintf(stderr, "dlopen failed: %s: %s\n", path.UTF8String, dlerror());
        return NO;
    }
    return YES;
}

static BOOL loadPrivateFrameworks(void) {
    return loadFramework(@"/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/CoreSimulator")
        && loadFramework(simulatorKitPath());
}

static Class resolveClass(NSString *objcName, NSString *mangledName) {
    Class cls = NSClassFromString(objcName);
    if (!cls && mangledName.length) cls = NSClassFromString(mangledName);
    return cls;
}

static void listClass(NSString *name, NSString *mangledName) {
    Class cls = resolveClass(name, mangledName);
    if (!cls) {
        printf("MISSING %s\n", name.UTF8String);
        return;
    }
    printf("CLASS %s\n", name.UTF8String);
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        printf("  %s\n", sel_getName(method_getName(methods[i])));
    }
    free(methods);
    unsigned int pcount = 0;
    objc_property_t *props = class_copyPropertyList(cls, &pcount);
    for (unsigned int i = 0; i < pcount; i++) {
        printf("  property %s\n", property_getName(props[i]));
    }
    free(props);
}

static void inspect(void) {
    listClass(@"SimServiceContext", nil);
    listClass(@"SimDeviceSet", nil);
    listClass(@"SimDevice", nil);
    listClass(@"SimulatorKit.SimDisplayView", @"_TtC12SimulatorKit14SimDisplayView");
    listClass(@"SimulatorKit.SimDeviceScreen", @"_TtC12SimulatorKit15SimDeviceScreen");
    listClass(@"SimulatorKit.SimDeviceLegacyHIDClient", @"_TtC12SimulatorKit24SimDeviceLegacyHIDClient");
    listClass(@"SimulatorKit.SimAccessibilityManager", @"_TtC12SimulatorKit23SimAccessibilityManager");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (!loadPrivateFrameworks()) return 2;
        NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"inspect";
        if ([mode isEqualToString:@"inspect"]) {
            inspect();
            return 0;
        }
        fprintf(stderr, "unknown mode: %s\n", mode.UTF8String);
        return 2;
    }
}
```

Create `spike/run.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/spike/out"
clang -fobjc-arc -fmodules -Wall -Wextra -Wno-deprecated-declarations \
  -framework Cocoa -framework IOSurface -framework ImageIO \
  -o "$ROOT/spike/probe" "$ROOT/spike/probe.m"
exec "$ROOT/spike/probe" "$@"
```

- [ ] **Step 4: Chạy check để thấy pass**

Run:

```bash
chmod +x spike/run.sh spike/check-inspect.sh
./spike/check-inspect.sh
```

Expected: `OK inspect`; `spike/out/inspect.txt` có danh sách method của từng class.

- [ ] **Step 5: Ghi lại kết quả quan trọng**

Ghi vào `spike/out/notes.md`:

- `SimulatorKit.SimDisplayView` có method `setDevice:`, `connectedScreen`, `initWithFrame:` hay không.
- `SimulatorKit.SimDeviceScreen` có `initWithDevice:screenID:`, `unmaskedSurface`, `maskedSurface`, `screenID` hay không.
- `SimulatorKit.SimAccessibilityManager` có method nào.
- `SimDeviceLegacyHIDClient` có method `send` hay selector tương đương.

Không commit file này.

---

### Task 2: Truy cập device qua CoreSimulator

**Files:**
- Modify: `spike/probe.m`
- Create: `spike/check-devices.sh`

**Interfaces:**
- Consumes: `loadPrivateFrameworks()`, `resolveClass()` từ Task 1.
- Produces: `probe devices --udid <UDID>` in `DEVICE <udid> | <name> | state=<state>` và `FOUND <udid> YES|NO`.
- Produces: `serviceContext(NSError **)`, `deviceSet(id, NSError **)`, `findDevice(id, NSString *)` cho Task 3-5.

- [ ] **Step 1: Viết check thất bại**

Create `spike/check-devices.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
UDID="$(xcrun simctl list devices booted -j | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for v in d["devices"].values() for x in v if x["state"]=="Booted"))')"
OUT="$("$ROOT/spike/run.sh" devices --udid "$UDID" 2>&1)"
print -r -- "$OUT" > "$ROOT/spike/out/devices.txt"
if ! print -r -- "$OUT" | grep -q "FOUND $UDID YES"; then
  print -u2 "device not found"
  exit 1
fi
print "OK devices $UDID"
```

Run:

```bash
chmod +x spike/check-devices.sh
./spike/check-devices.sh
```

Expected: FAIL với `unknown mode: devices`.

- [ ] **Step 2: Thêm NSInvocation helpers và mode devices**

Append vào `spike/probe.m` trước `main`:

```objc
static id invoke0(id target, SEL sel) {
    NSMethodSignature *sig = [target methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = target;
    inv.selector = sel;
    [inv invoke];
    __unsafe_unretained id result = nil;
    [inv getReturnValue:&result];
    return result;
}

static id invoke1(id target, SEL sel, id arg) {
    NSMethodSignature *sig = [target methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = target;
    inv.selector = sel;
    [inv setArgument:&arg atIndex:2];
    [inv invoke];
    __unsafe_unretained id result = nil;
    [inv getReturnValue:&result];
    return result;
}

static id invoke0WithError(id target, SEL sel, NSError **error) {
    NSMethodSignature *sig = [target methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = target;
    inv.selector = sel;
    NSError *__autoreleasing local = nil;
    NSError *__autoreleasing *ptr = &local;
    [inv setArgument:&ptr atIndex:2];
    [inv invoke];
    __unsafe_unretained id result = nil;
    [inv getReturnValue:&result];
    if (error) *error = local;
    return result;
}

static id invoke1WithError(id target, SEL sel, id arg, NSError **error) {
    NSMethodSignature *sig = [target methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = target;
    inv.selector = sel;
    [inv setArgument:&arg atIndex:2];
    NSError *__autoreleasing local = nil;
    NSError *__autoreleasing *ptr = &local;
    [inv setArgument:&ptr atIndex:3];
    [inv invoke];
    __unsafe_unretained id result = nil;
    [inv getReturnValue:&result];
    if (error) *error = local;
    return result;
}

static NSString *argValue(int argc, const char *argv[], NSString *flag) {
    for (int i = 2; i + 1 < argc; i++) {
        NSString *key = [NSString stringWithUTF8String:argv[i]];
        if ([key isEqualToString:flag]) return [NSString stringWithUTF8String:argv[i + 1]];
    }
    return nil;
}

static id safeValue(id object, NSString *key) {
    @try {
        return [object valueForKey:key];
    } @catch (NSException *exception) {
        return nil;
    }
}

static id serviceContext(NSError **error) {
    Class cls = NSClassFromString(@"SimServiceContext");
    SEL sel = NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:");
    return invoke1WithError((id)cls, sel, xcodeDeveloperDir(), error);
}

static id defaultDeviceSet(id ctx, NSError **error) {
    return invoke0WithError(ctx, NSSelectorFromString(@"defaultDeviceSetWithError:"), error);
}

static NSArray *deviceList(id set) {
    SEL sel = NSSelectorFromString(@"devices");
    if ([set respondsToSelector:sel]) {
        id value = invoke0(set, sel);
        if ([value isKindOfClass:[NSArray class]]) return value;
    }
    id value = safeValue(set, @"devices");
    if ([value isKindOfClass:[NSArray class]]) return value;
    return @[];
}

static NSString *deviceUDID(id device) {
    id uuid = safeValue(device, @"UDID");
    if ([uuid isKindOfClass:[NSUUID class]]) return [uuid UUIDString];
    return [uuid description];
}

static id findDevice(id set, NSString *udid) {
    for (id device in deviceList(set)) {
        if ([[deviceUDID(device) lowercaseString] isEqualToString:[udid lowercaseString]]) return device;
    }
    return nil;
}

static void devicesMode(NSString *wantedUDID) {
    NSError *error = nil;
    id ctx = serviceContext(&error);
    if (!ctx) {
        printf("ERROR context: %s\n", error.localizedDescription.UTF8String);
        exit(2);
    }
    id set = defaultDeviceSet(ctx, &error);
    if (!set) {
        printf("ERROR deviceSet: %s\n", error.localizedDescription.UTF8String);
        exit(2);
    }
    for (id device in deviceList(set)) {
        NSString *name = safeValue(device, @"name");
        NSString *state = safeValue(device, @"stateString");
        if (!state) state = [safeValue(device, @"state") description];
        printf("DEVICE %s | %s | state=%s\n", deviceUDID(device).UTF8String, name.UTF8String, state.UTF8String);
    }
    if (wantedUDID) {
        id device = findDevice(set, wantedUDID);
        printf("FOUND %s %s\n", wantedUDID.UTF8String, device ? "YES" : "NO");
    }
}
```

Sửa dispatch trong `main`:

```objc
        if ([mode isEqualToString:@"inspect"]) {
            inspect();
            return 0;
        }
        if ([mode isEqualToString:@"devices"]) {
            devicesMode(argValue(argc, argv, @"--udid"));
            return 0;
        }
```

- [ ] **Step 3: Chạy check để thấy pass**

Run:

```bash
./spike/check-devices.sh
```

Expected: `OK devices <UDID>`; log có device iPhone Air và `FOUND <UDID> YES`.

- [ ] **Step 4: Ghi lại selector hoạt động**

Ghi vào `spike/out/notes.md`: selector nào trả device, tên class thật của device set, và bất kỳ lỗi KVC nào. Không commit.

---

### Task 3: Render iOS screen

**Files:**
- Modify: `spike/probe.m`
- Create: `spike/check-render.sh`

**Interfaces:**
- Consumes: `serviceContext`, `defaultDeviceSet`, `findDevice` từ Task 2.
- Produces: `probe render --udid <UDID> --duration <seconds> --out <png>`.
- Produces: log `CONNECTED_SCREEN YES|NO`, `PIXEL_SIZE <w>x<h>`, `FRAME_CHANGES <n>`, `FPS_ESTIMATE <n>`, `CAPTURED <path>` hoặc `CAPTURE_FAILED`.

- [ ] **Step 1: Viết check thất bại**

Create `spike/check-render.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
UDID="$(xcrun simctl list devices booted -j | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for v in d["devices"].values() for x in v if x["state"]=="Booted"))')"
OUT="$ROOT/spike/out/render.txt"
OUTPNG="$ROOT/spike/out/render-ios.png"
"$ROOT/spike/run.sh" render --udid "$UDID" --duration 8 --out "$OUTPNG" > "$OUT" 2>&1 &
PID=$!
sleep 10
wait $PID || true
if ! grep -q "CONNECTED_SCREEN YES" "$OUT"; then
  print -u2 "render not connected"
  cat "$OUT"
  exit 1
fi
if ! grep -qE "PIXEL_SIZE [0-9]+x[0-9]+" "$OUT"; then
  print -u2 "pixel size missing"
  exit 1
fi
print "OK render"
```

Run:

```bash
chmod +x spike/check-render.sh
./spike/check-render.sh
```

Expected: FAIL với `unknown mode: render`.

- [ ] **Step 2: Thêm render mode**

Thêm vào đầu `spike/probe.m`:

```objc
#import <IOSurface/IOSurface.h>
#import <ImageIO/ImageIO.h>
```

Append trước `main`:

```objc
static NSWindow *gWindow = nil;
static NSView *gDisplayView = nil;

static void saveWindowPNG(NSWindow *window, NSString *path) {
    CGWindowID windowID = 0;
    CFArrayRef infos = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    for (NSDictionary *info in (__bridge NSArray *)infos) {
        if ([info[(id)kCGWindowOwnerPID] intValue] == getpid()) {
            windowID = [info[(id)kCGWindowNumber] unsignedIntValue];
            break;
        }
    }
    if (infos) CFRelease(infos);
    if (!windowID) {
        printf("WINDOW_ID 0\n");
        return;
    }
    printf("WINDOW_ID %u\n", windowID);
    CGImageRef image = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow, windowID, kCGWindowImageBoundsIgnoreFraming);
    if (!image) {
        printf("CAPTURE_FAILED\n");
        return;
    }
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, NULL);
    if (!dest) {
        CGImageRelease(image);
        printf("CAPTURE_DEST_FAILED\n");
        return;
    }
    CGImageDestinationAddImage(dest, image, NULL);
    CGImageDestinationFinalize(dest);
    CFRelease(dest);
    CGImageRelease(image);
    printf("CAPTURED %s\n", path.UTF8String);
}

static id connectedScreen(NSView *view) {
    SEL sel = NSSelectorFromString(@"connectedScreen");
    if (![view respondsToSelector:sel]) return nil;
    return invoke0(view, sel);
}

static id screenPixelSize(id screen) {
    SEL sel = NSSelectorFromString(@"pixelSize");
    if (![screen respondsToSelector:sel]) return nil;
    NSMethodSignature *sig = [screen methodSignatureForSelector:sel];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = screen;
    inv.selector = sel;
    [inv invoke];
    CGSize size = CGSizeZero;
    if (sig.methodReturnLength == sizeof(CGSize)) {
        [inv getReturnValue:&size];
    }
    return [NSValue valueWithSize:NSMakeSize(size.width, size.height)];
}

static uint64_t hashSurface(id screen) {
    SEL sel = NSSelectorFromString(@"unmaskedSurface");
    if (![screen respondsToSelector:sel]) return 0;
    IOSurfaceRef surface = (__bridge IOSurfaceRef)invoke0(screen, sel);
    if (!surface) return 0;
    IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
    size_t bytesPerRow = IOSurfaceGetBytesPerRow(surface);
    size_t height = IOSurfaceGetHeight(surface);
    uint8_t *base = IOSurfaceGetBaseAddress(surface);
    uint64_t hash = 1469598103934665603ULL;
    for (size_t y = 0; y < height; y += 64) {
        uint8_t *row = base + y * bytesPerRow;
        for (size_t x = 0; x < bytesPerRow; x += 64) {
            hash ^= row[x];
            hash *= 1099511628211ULL;
        }
    }
    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
    return hash;
}

static void renderMode(NSString *udid, double duration, NSString *outPath) {
    NSError *error = nil;
    id ctx = serviceContext(&error);
    id set = defaultDeviceSet(ctx, &error);
    id device = findDevice(set, udid);
    if (!device) {
        printf("ERROR device not found: %s\n", udid.UTF8String);
        exit(2);
    }

    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    gWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(80, 80, 430, 932)
                                          styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    gWindow.title = @"OpenSim Spike";
    Class viewClass = resolveClass(@"SimulatorKit.SimDisplayView", @"_TtC12SimulatorKit14SimDisplayView");
    if (!viewClass) {
        printf("ERROR SimDisplayView missing\n");
        exit(2);
    }
    gDisplayView = [[viewClass alloc] initWithFrame:gWindow.contentView.bounds];
    gDisplayView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [gWindow.contentView addSubview:gDisplayView];

    SEL setDevice = NSSelectorFromString(@"setDevice:");
    if ([gDisplayView respondsToSelector:setDevice]) {
        [gDisplayView performSelector:setDevice withObject:device];
        printf("SET_DEVICE YES\n");
    } else {
        printf("SET_DEVICE NO\n");
    }

    [gWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    __block uint64_t lastHash = 0;
    __block int changes = 0;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, (uint64_t)(NSEC_PER_SEC / 60.0), NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        id screen = connectedScreen(gDisplayView);
        if (!screen) return;
        uint64_t hash = hashSurface(screen);
        if (hash != 0 && hash != lastHash) {
            changes += 1;
            lastHash = hash;
        }
    });
    dispatch_resume(timer);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id screen = connectedScreen(gDisplayView);
        printf("CONNECTED_SCREEN %s\n", screen ? "YES" : "NO");
        if (screen) {
            NSValue *size = screenPixelSize(screen);
            if (size) {
                NSSize s = [size sizeValue];
                printf("PIXEL_SIZE %.0fx%.0f\n", s.width, s.height);
            } else {
                printf("PIXEL_SIZE unavailable\n");
            }
        }
        if (outPath.length) saveWindowPNG(gWindow, outPath);
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        printf("FRAME_CHANGES %d\n", changes);
        printf("FPS_ESTIMATE %.1f\n", duration > 0 ? changes / duration : 0.0);
        [NSApp terminate:nil];
    });

    [NSApp run];
}
```

Sửa dispatch trong `main`:

```objc
        if ([mode isEqualToString:@"render"]) {
            NSString *udid = argValue(argc, argv, @"--udid");
            NSString *outPath = argValue(argc, argv, @"--out");
            NSString *durationString = argValue(argc, argv, @"--duration") ?: @"8";
            renderMode(udid, durationString.doubleValue, outPath);
            return 0;
        }
```

- [ ] **Step 3: Chạy check để thấy pass**

Run:

```bash
./spike/check-render.sh
```

Expected: `OK render`; `spike/out/render.txt` có `CONNECTED_SCREEN YES`, `PIXEL_SIZE`, `FRAME_CHANGES`/`FPS_ESTIMATE` (ước lượng; có thể bằng 0 nếu màn hình đang tĩnh).

- [ ] **Step 4: Xem ảnh bằng chứng**

Mở `spike/out/render-ios.png` bằng tool Read (image). Xác nhận nhìn thấy màn hình iPhone Air. Nếu `CGWindowListCreateImage` không compile được trên SDK 27, bỏ hàm capture khỏi probe và dùng `screencapture -x` bên ngoài; ghi rõ trong report. Nếu `CAPTURE_FAILED`, chạy:

```bash
screencapture -x /tmp/opensim-spike-desktop.png
```

rồi đọc ảnh desktop; ghi rõ trong report là cửa sổ đã hiển thị nhưng capture nội bộ thất bại.

- [ ] **Step 5: Ghi số đo**

Ghi vào `spike/out/notes.md`:

- `CONNECTED_SCREEN`, `PIXEL_SIZE`, `FRAME_CHANGES`, `FPS_ESTIMATE`.
- Ghi rõ `FPS_ESTIMATE` là ước lượng frame-change ở 60 Hz, không phải số đo Instruments; nếu màn hình tĩnh, 0 là bình thường.
- CPU/RSS của probe trong 8 giây (chạy `ps -o pid,%cpu,rss,comm -p <pid>` trong lúc probe chạy).
- Cửa sổ hiển thị đúng màn hình hay đen/trắng.
- Nếu `FPS_UNAVAILABLE`, ghi lý do (`unmaskedSurface` thiếu hoặc selector không expose).

---

### Task 4: Tap và type

**Files:**
- Modify: `spike/probe.m`
- Create: `spike/check-input.sh`

**Interfaces:**
- Consumes: `renderMode` setup, `gWindow`, `gDisplayView` từ Task 3.
- Produces: `probe tap --udid <UDID> --x <0..1> --y <0..1> --duration <seconds>`.
- Produces: `probe type --udid <UDID> --text <string> --duration <seconds>`.
- Produces: log `TAP <x> <y>`, `HIT <class>`, `TYPE <text>`.

- [ ] **Step 1: Viết check thất bại**

Create `spike/check-input.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
UDID="$(xcrun simctl list devices booted -j | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for v in d["devices"].values() for x in v if x["state"]=="Booted"))')"
xcrun simctl launch "$UDID" com.apple.Preferences >/dev/null
sleep 2
BEFORE="$ROOT/spike/out/input-before.png"
AFTER="$ROOT/spike/out/input-after.png"
xcrun simctl io "$UDID" screenshot "$BEFORE" >/dev/null
"$ROOT/spike/run.sh" tap --udid "$UDID" --x 0.5 --y 0.12 --duration 6 > "$ROOT/spike/out/tap.txt" 2>&1 || true
sleep 1
xcrun simctl io "$UDID" screenshot "$AFTER" >/dev/null
BEFORE_HASH="$(shasum -a 256 "$BEFORE" | awk '{print $1}')"
AFTER_HASH="$(shasum -a 256 "$AFTER" | awk '{print $1}')"
print "before=$BEFORE_HASH after=$AFTER_HASH"
if [[ "$BEFORE_HASH" == "$AFTER_HASH" ]]; then
  print -u2 "screen did not change after tap"
  exit 1
fi
print "OK input tap"
```

Run:

```bash
chmod +x spike/check-input.sh
./spike/check-input.sh
```

Expected: FAIL vì chưa có mode `tap`; nếu mode tap có nhưng input không tác dụng, hash sẽ giống nhau và check fail.

- [ ] **Step 2: Thêm tap và type mode**

Append trước `main`:

```objc
static void sendMouseTap(NSView *view, NSWindow *window, double nx, double ny) {
    NSRect bounds = view.bounds;
    NSPoint point = NSMakePoint(nx * bounds.size.width, (1.0 - ny) * bounds.size.height);
    id hit = [view hitTest:point];
    printf("HIT %s\n", hit ? NSStringFromClass([hit class]).UTF8String : "nil");
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                       location:point
                                  modifierFlags:0
                                      timestamp:NSProcessInfo.processInfo.systemUptime
                                   windowNumber:window.windowNumber
                                        context:nil
                                    eventNumber:1
                                     clickCount:1
                                       pressure:1.0];
    NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                                     location:point
                                modifierFlags:0
                                    timestamp:NSProcessInfo.processInfo.systemUptime
                                 windowNumber:window.windowNumber
                                      context:nil
                                  eventNumber:2
                                   clickCount:1
                                     pressure:1.0];
    [NSApp sendEvent:down];
    usleep(80000);
    [NSApp sendEvent:up];
    printf("TAP %.3f %.3f\n", nx, ny);
}

static unsigned short keyCodeForCharacter(unichar ch) {
    switch (ch) {
        case 'a': return 0;
        case 'b': return 11;
        case 'c': return 8;
        case 'd': return 2;
        case 'e': return 14;
        case 'f': return 3;
        case 'g': return 5;
        case 'h': return 4;
        case 'i': return 34;
        case 'j': return 38;
        case 'k': return 40;
        case 'l': return 37;
        case 'm': return 46;
        case 'n': return 45;
        case 'o': return 31;
        case 'p': return 35;
        case 'q': return 12;
        case 'r': return 15;
        case 's': return 1;
        case 't': return 17;
        case 'u': return 32;
        case 'v': return 9;
        case 'w': return 13;
        case 'x': return 7;
        case 'y': return 16;
        case 'z': return 6;
        default: return 0;
    }
}

static void sendText(NSView *view, NSWindow *window, NSString *text) {
    NSPoint point = NSMakePoint(0, 0);
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar ch = [text characterAtIndex:i];
        NSString *chars = [NSString stringWithCharacters:&ch length:1];
        unsigned short code = keyCodeForCharacter(ch);
        NSEvent *down = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                         location:point
                                    modifierFlags:0
                                        timestamp:NSProcessInfo.processInfo.systemUptime
                                     windowNumber:window.windowNumber
                                          context:nil
                                       characters:chars
                     charactersIgnoringModifiers:chars
                                        isARepeat:NO
                                          keyCode:code];
        NSEvent *up = [NSEvent keyEventWithType:NSEventTypeKeyUp
                                       location:point
                                  modifierFlags:0
                                      timestamp:NSProcessInfo.processInfo.systemUptime
                                   windowNumber:window.windowNumber
                                        context:nil
                                     characters:chars
                   charactersIgnoringModifiers:chars
                                      isARepeat:NO
                                        keyCode:code];
        [NSApp sendEvent:down];
        [NSApp sendEvent:up];
        usleep(30000);
    }
    printf("TYPE %s\n", text.UTF8String);
}

static void inputMode(NSString *udid, double duration, double nx, double ny, NSString *text) {
    NSError *error = nil;
    id ctx = serviceContext(&error);
    id set = defaultDeviceSet(ctx, &error);
    id device = findDevice(set, udid);
    if (!device) {
        printf("ERROR device not found: %s\n", udid.UTF8String);
        exit(2);
    }
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    gWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(80, 80, 430, 932)
                                          styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    gWindow.title = @"OpenSim Spike Input";
    Class viewClass = resolveClass(@"SimulatorKit.SimDisplayView", @"_TtC12SimulatorKit14SimDisplayView");
    if (!viewClass) {
        printf("ERROR SimDisplayView missing\n");
        exit(2);
    }
    gDisplayView = [[viewClass alloc] initWithFrame:gWindow.contentView.bounds];
    gDisplayView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [gWindow.contentView addSubview:gDisplayView];
    SEL setDevice = NSSelectorFromString(@"setDevice:");
    if ([gDisplayView respondsToSelector:setDevice]) {
        [gDisplayView performSelector:setDevice withObject:device];
    }
    [gWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (nx >= 0 && ny >= 0) sendMouseTap(gDisplayView, gWindow, nx, ny);
        if (text.length) sendText(gDisplayView, gWindow, text);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSApp terminate:nil];
    });
    [NSApp run];
}
```

Sửa dispatch trong `main`:

```objc
        if ([mode isEqualToString:@"tap"]) {
            NSString *udid = argValue(argc, argv, @"--udid");
            double x = [argValue(argc, argv, @"--x") doubleValue];
            double y = [argValue(argc, argv, @"--y") doubleValue];
            double duration = [argValue(argc, argv, @"--duration") doubleValue] ?: 6;
            NSString *text = argValue(argc, argv, @"--text");
            inputMode(udid, duration, x, y, text);
            return 0;
        }
        if ([mode isEqualToString:@"type"]) {
            NSString *udid = argValue(argc, argv, @"--udid");
            NSString *text = argValue(argc, argv, @"--text") ?: @"hello";
            double duration = [argValue(argc, argv, @"--duration") doubleValue] ?: 6;
            inputMode(udid, duration, -1, -1, text);
            return 0;
        }
```

- [ ] **Step 3: Chạy check để thấy pass**

Run:

```bash
./spike/check-input.sh
```

Expected: `OK input tap`; `before` và `after` hash khác nhau. Hash khác là điều kiện cần, chưa đủ; mở `input-after.png` để xác nhận Settings search field được focus hoặc bàn phím hiện lên. Nếu hash khác nhưng màn hình không đổi theo ý muốn, chọn tọa độ khác từ ảnh và chạy lại; ghi lại tọa độ đã dùng.

- [ ] **Step 4: Kiểm tra type**

Run:

```bash
UDID="$(xcrun simctl list devices booted -j | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for v in d["devices"].values() for x in v if x["state"]=="Booted"))')"
xcrun simctl io "$UDID" screenshot spike/out/type-before.png
./spike/run.sh tap --udid "$UDID" --x 0.5 --y 0.12 --text "hello" --duration 6 > spike/out/type.txt 2>&1 || true
xcrun simctl io "$UDID" screenshot spike/out/type-after.png
shasum -a 256 spike/out/type-before.png spike/out/type-after.png
```

Expected: hash khác nhau; ảnh `type-after.png` cho thấy text hoặc bàn phím thay đổi. Nếu không, thử gọi `[gDisplayView keyDown:down]` trực tiếp thay vì `[NSApp sendEvent:]`, hoặc dùng `IndigoHIDMessageForKeyboardNSEvent`; ghi lại kết quả.

- [ ] **Step 5: Ghi số đo**

Ghi vào `spike/out/notes.md`: tọa độ tap, `HIT` class, hash before/after, text đã gõ, thời gian từ tap đến khi ảnh đổi (nếu đo được), và mọi fallback đã thử.

---

### Task 5: Accessibility tree

**Files:**
- Modify: `spike/probe.m`
- Create: `spike/check-a11y.sh`

**Interfaces:**
- Produces: `probe a11y --udid <UDID>`.
- Produces: log `A11Y_CANDIDATE <selector> = <value>` hoặc `A11Y_UNAVAILABLE <reason>`.

- [ ] **Step 1: Viết check**

Create `spike/check-a11y.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
UDID="$(xcrun simctl list devices booted -j | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for v in d["devices"].values() for x in v if x["state"]=="Booted"))')"
OUT="$("$ROOT/spike/run.sh" a11y --udid "$UDID" 2>&1)"
print -r -- "$OUT" > "$ROOT/spike/out/a11y.txt"
if ! print -r -- "$OUT" | grep -qE "A11Y_CANDIDATE|A11Y_UNAVAILABLE"; then
  print -u2 "a11y probe produced no decision"
  exit 1
fi
print "OK a11y probe"
```

Run sau khi thêm mode; expected: PASS với candidate hoặc unavailable.

- [ ] **Step 2: Thêm a11y introspection**

Append trước `main`:

```objc
static void a11yMode(NSString *udid) {
    listClass(@"SimulatorKit.SimAccessibilityManager", @"_TtC12SimulatorKit23SimAccessibilityManager");
    Class cls = resolveClass(@"SimulatorKit.SimAccessibilityManager", @"_TtC12SimulatorKit23SimAccessibilityManager");
    if (!cls) {
        printf("A11Y_UNAVAILABLE missing SimAccessibilityManager\n");
        return;
    }
    id manager = nil;
    SEL newSel = NSSelectorFromString(@"new");
    if ([cls respondsToSelector:newSel]) manager = invoke0((id)cls, newSel);
    if (!manager) {
        printf("A11Y_UNAVAILABLE cannot instantiate\n");
        return;
    }
    NSArray *candidates = @[@"rootElement", @"accessibilityElement", @"accessibilityTree", @"snapshot", @"elements", @"elementAtPoint:"];
    for (NSString *name in candidates) {
        SEL sel = NSSelectorFromString(name);
        if ([manager respondsToSelector:sel]) {
            id value = nil;
            if ([name hasSuffix:@":"] && [name isEqualToString:@"elementAtPoint:"]) {
                NSPoint point = NSMakePoint(0, 0);
                NSMethodSignature *sig = [manager methodSignatureForSelector:sel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                inv.target = manager;
                inv.selector = sel;
                [inv setArgument:&point atIndex:2];
                [inv invoke];
                [inv getReturnValue:&value];
            } else {
                value = invoke0(manager, sel);
            }
            printf("A11Y_CANDIDATE %s = %s\n", name.UTF8String, [[value description] UTF8String]);
        }
    }
    printf("A11Y_DONE\n");
}
```

Sửa dispatch trong `main`:

```objc
        if ([mode isEqualToString:@"a11y"]) {
            a11yMode(argValue(argc, argv, @"--udid"));
            return 0;
        }
```

- [ ] **Step 3: Chạy check**

Run:

```bash
chmod +x spike/check-a11y.sh
./spike/check-a11y.sh
```

Expected: PASS; output có `A11Y_CANDIDATE` nếu tìm được getter, hoặc `A11Y_UNAVAILABLE <reason>` nếu class/khởi tạo không dùng được.

- [ ] **Step 4: Quyết định fallback**

Nếu không có candidate trả về element tree thực sự:

- Ghi rõ `A11Y_PRIVATE=NO`.
- Plan 2 dùng XCUITest helper làm đường chính.
- Ghi chi phí ước tính vào report: thêm test bundle, runner, local socket, 2-4 ngày công.

Nếu có candidate nhưng chỉ trả về đối tượng rỗng/không có children:

- Ghi rõ output thực tế.
- Thử tối đa 20 phút để tìm method lấy children/attributes; hết giờ thì chốt fallback, không đoán.

---

### Task 6: watchOS/tvOS runtime check

**Files:**
- Create: `spike/check-platforms.sh`

**Interfaces:**
- Produces: `WATCH_RUNTIME installed|missing`, `TV_RUNTIME installed|missing`, và command cài đặt nếu missing.

- [ ] **Step 1: Viết check**

Create `spike/check-platforms.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
OUT="$ROOT/spike/out/platforms.txt"
{
  print "RUNTIMES"
  xcrun simctl list runtimes -j | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); [print(r.get("identifier"), "|", r.get("name")) for r in d.get("runtimes",[])]'
  WATCH="$(xcrun simctl list runtimes -j | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((r["identifier"] for r in d.get("runtimes",[]) if "watchOS" in r.get("identifier","") or "watchOS" in r.get("name","")), ""))')"
  TV="$(xcrun simctl list runtimes -j | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((r["identifier"] for r in d.get("runtimes",[]) if "tvOS" in r.get("identifier","") or "tvOS" in r.get("name","")), ""))')"
  if [[ -z "$WATCH" ]]; then
    print "WATCH_RUNTIME missing"
    print "INSTALL_WATCH xcodebuild -downloadPlatform watchOS"
  else
    print "WATCH_RUNTIME installed $WATCH"
  fi
  if [[ -z "$TV" ]]; then
    print "TV_RUNTIME missing"
    print "INSTALL_TV xcodebuild -downloadPlatform tvOS"
  else
    print "TV_RUNTIME installed $TV"
  fi
} | tee "$OUT"
```

Run:

```bash
chmod +x spike/check-platforms.sh
./spike/check-platforms.sh
```

Expected hiện tại: `WATCH_RUNTIME missing` và `TV_RUNTIME missing`. Đây là kết quả hợp lệ; **không tự tải runtime**.

- [ ] **Step 2: Quyết định**

Nếu runtime missing:

- Ghi `WATCH=BLOCKED_RUNTIME_MISSING`, `TV=BLOCKED_RUNTIME_MISSING` vào report.
- Không tải runtime trong Plan 0.
- Plan 6 sẽ cài runtime và chạy probe render/input của watch/tv.

Nếu runtime có sẵn (owner đã cài):

- Tạo device:
  ```bash
  xcrun simctl create "OpenSim Spike Watch" com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-12-46mm "$WATCH_RUNTIME"
  xcrun simctl create "OpenSim Spike TV" com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K "$TV_RUNTIME"
  ```
- Boot từng device, chạy `probe render` và `probe tap`, ghi kết quả như Task 3-4.
- Xoá device spike sau khi xong: `xcrun simctl delete <UDID>`.

---

### Task 7: Report và chốt quyết định

**Files:**
- Create: `docs/superpowers/spikes/2026-10-19-private-api-spike.md`
- Create: `docs/superpowers/spikes/artifacts/render-ios.png` (nếu capture được)
- Modify: `docs/superpowers/specs/2026-10-19-open-simulator-design.md` (chỉ khi kết quả làm đổi quyết định)

**Interfaces:**
- Consumes: tất cả output trong `spike/out/`.
- Produces: báo cáo PASS/FAIL/BLOCKED với quyết định render/input/a11y/watch/tv và next step cho Plan 1.

- [ ] **Step 1: Viết report**

Create `docs/superpowers/spikes/2026-10-19-private-api-spike.md`:

```markdown
# OpenSim Plan 0 — Private API Spike Report

- Ngày: 2026-10-19
- Máy: macOS 27.0.1, Xcode 27.1 (27A9275)
- Device: iPhone Air, iOS 27.0
- Thời gian chạy: ghi số phút thực tế sau khi chạy

## Kết quả

| Khả năng | Kết quả | Bằng chứng | Quyết định |
|---|---|---|---|
| Tìm device CoreSimulator | PASS/FAIL | `spike/out/devices.txt` | |
| Render iOS | PASS/FAIL | `CONNECTED_SCREEN`, `PIXEL_SIZE`, `FPS`, ảnh | |
| Tap iOS | PASS/FAIL | hash before/after, `HIT` | |
| Type iOS | PASS/FAIL | hash before/after, ảnh | |
| Accessibility tree | PASS/UNAVAILABLE | `A11Y_CANDIDATE` hoặc lý do | |
| watchOS | PASS/BLOCKED | runtime + render/tap | |
| tvOS | PASS/BLOCKED | runtime + render/tap | |

## Số đo

- Pixel size:
- FPS:
- CPU/RSS của probe:
- Tap latency ước lượng:
- Capture ảnh cửa sổ: thành công/thất bại + lý do.

## API/selector hoạt động

- Device context:
- Device set:
- Display view:
- Screen:
- Input:
- Accessibility:

## Quyết định

- Render: `SimDisplayView` / IOSurface tự dựng / screenshot polling.
- Input: view event / IndigoHID / XCUITest.
- Accessibility: private / XCUITest helper.
- watch/tv: verified / blocked runtime missing (Plan 6).
- Rủi ro còn lại cho Plan 1.

## Việc tiếp theo

1. Nếu render + input PASS: viết Plan 1 (Core + Bridge + lifecycle + CLI).
2. Nếu render PASS nhưng input FAIL: Plan 1 vẫn làm lifecycle; Plan 2 mở đầu bằng HID fallback.
3. Nếu render FAIL: dừng Plan 1, viết plan riêng cho IOSurface/screenshot fallback.
```

- [ ] **Step 2: Copy artifact**

Nếu capture thành công:

```bash
cp spike/out/render-ios.png docs/superpowers/spikes/artifacts/render-ios.png
cp spike/out/input-after.png docs/superpowers/spikes/artifacts/input-after.png
```

Nếu capture thất bại, ghi rõ trong report; không fake ảnh.

- [ ] **Step 3: Tự kiểm tra report với spec**

Đọc lại mục 5.4, 16 (Plan 0), 18 của spec. Trả lời:

- Plan 0 exit criteria đã đạt hay blocked?
- Có quyết định nào làm đổi spec không?
- Nếu watch/tv blocked, spec có ghi rõ Plan 6 chịu trách nhiệm không?

Nếu có thay đổi, sửa spec bằng Edit và ghi lý do trong commit.

- [ ] **Step 4: Commit plan + report**

```bash
git add docs/superpowers/plans docs/superpowers/spikes docs/superpowers/specs
git commit -m "docs: add private API spike report and plan 0"
```

Kiểm tra lại hash bằng `git log -1 --oneline`; không báo hash trước khi lệnh chạy xong.

---

## Self-Review Checklist

- [ ] Mỗi task có deliverable độc lập và check thất bại trước khi implement.
- [ ] Không có bước nào yêu cầu tải runtime mà chưa có đồng ý của owner.
- [ ] Không có tham chiếu tới file production chưa tồn tại.
- [ ] Code dùng đúng selector đã kiểm tra: `sharedServiceContextForDeveloperDir:error:`, `defaultDeviceSetWithError:`, `setDevice:`, `connectedScreen`, `pixelSize`, `unmaskedSurface`.
- [ ] Nếu selector không expose, probe in `MISSING`/`UNAVAILABLE` và report ghi fallback, không crash im lặng.
- [ ] Report có đủ số đo hoặc ghi rõ lý do không đo được.
- [ ] Không commit `spike/`.
- [ ] Không sửa spec ngoài các quyết định đã có bằng chứng.
