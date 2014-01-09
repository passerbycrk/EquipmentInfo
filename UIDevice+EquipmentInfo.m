//
//  UIDevice+EquipmentInfo.m
//
//  Created by Ray Zhang on 13-1-8.
//
//  This Device Category Depand on CoreTelephony, IOKit Frameworks and libMobileGestalt Dynamic Library
//

#import "UIDevice+EquipmentInfo.h"

@implementation UIDevice (EquipmentInfo)

// Core Telephony Device Information
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
typedef struct CTResult {
    int flag;
    int a;
} CTResult;

extern struct CTServerConnection *_CTServerConnectionCreate(CFAllocatorRef, int (*)(void *, CFStringRef, CFDictionaryRef, void *), int *);
extern void _CTServerConnectionCopyMobileEquipmentInfo(CTResult *status, CFTypeRef connection, CFMutableDictionaryRef *equipmentInfo);

static int callback(void *connection, CFStringRef string, CFDictionaryRef dictionary, void *data) {
    return 0;
}

extern const NSString * const kCTMobileEquipmentInfoERIVersion;
extern const NSString * const kCTMobileEquipmentInfoICCID;
extern const NSString * const kCTMobileEquipmentInfoIMEI;
extern const NSString * const kCTMobileEquipmentInfoMEID;
extern const NSString * const kCTMobileEquipmentInfoPRLVersion;
static const NSString * const kCTMobileEquipmentInfoIMSI;

- (NSString *)mobileDeviceInfoForKey:(const NSString *)key {
    NSString *retVal = nil;
    CFTypeRef ctsc = _CTServerConnectionCreate(kCFAllocatorDefault, callback, NULL);
    if (ctsc) {
        struct CTResult result;
        CFMutableDictionaryRef equipmentInfo = nil;
        _CTServerConnectionCopyMobileEquipmentInfo(&result, ctsc, &equipmentInfo);
        if (equipmentInfo) {
            retVal = [NSString stringWithString:CFDictionaryGetValue(equipmentInfo, key)];
            CFRelease(equipmentInfo);
        }
        CFRelease(ctsc);
    }
    return retVal;
}

- (NSString *)ERIVersion {
    return [self mobileDeviceInfoForKey:kCTMobileEquipmentInfoERIVersion];
}

- (NSString *)ICCID {
    return [self mobileDeviceInfoForKey:kCTMobileEquipmentInfoICCID];
}

- (NSString *)IMEI {
    //To avoid crash on 64-bit runtime, we use shared memory to fetch IMEI instead
    //return [self mobileDeviceInfoForKey:kCTMobileEquipmentInfoIMEI];
    return [[IMEIManager sharedManager] IMEI];
}

- (NSString *)IMSI {
    return [self mobileDeviceInfoForKey:kCTMobileEquipmentInfoIMSI];
}

- (NSString *)MEID {
    return [self mobileDeviceInfoForKey:kCTMobileEquipmentInfoMEID];
}

- (NSString *)PRLVersion {
    return [self mobileDeviceInfoForKey:kCTMobileEquipmentInfoPRLVersion];
}

// UIKit Device Information
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
extern NSString *MGCopyAnswer(CFStringRef);
static const CFStringRef kMobileDeviceUniqueIdentifier = CFSTR("UniqueDeviceID");
static const CFStringRef kMobileDeviceCPUArchitecture = CFSTR("CPUArchitecture");
static const CFStringRef kMobileDeviceSerialNumber = CFSTR("SerialNumber");

- (NSString *)UDID {
    return [MGCopyAnswer(kMobileDeviceUniqueIdentifier) autorelease];
}

- (NSString *)CPUArchitecture {
    return [MGCopyAnswer(kMobileDeviceCPUArchitecture) autorelease];
}

- (NSString *)serialNumber {
    return [MGCopyAnswer(kMobileDeviceSerialNumber) autorelease];
}

// IOKit Device Information
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#import <IOKit/IOKitLib.h>
static const CFStringRef kIODeviceModel = CFSTR("model");

static const CFStringRef kIODeviceIMEI = CFSTR("device-imei");
static const CFStringRef kIODeviceSerialNumber = CFSTR("serial-number");

static const CFStringRef kIOPlatformUUID = CFSTR("IOPlatformUUID");
static const CFStringRef kIOPlatformSerialNumber = CFSTR("IOPlatformSerialNumber");

- (NSString *)IODeviceInfoForKey:(CFStringRef)key {
    NSString *retVal = nil;
    io_registry_entry_t entry = IORegistryGetRootEntry(kIOMasterPortDefault);
    if (entry) {
        CFTypeRef property = IORegistryEntrySearchCFProperty(entry, kIODeviceTreePlane, key, kCFAllocatorDefault, kIORegistryIterateRecursively);
        if (property) {
            CFTypeID typeID = CFGetTypeID(property);
            if (CFStringGetTypeID() == typeID) {
                retVal = [NSString stringWithString:(NSString *)property];
            } else if (CFDataGetTypeID() == typeID) {
                CFStringRef modelString = CFStringCreateWithBytes(kCFAllocatorDefault,
                                                                  CFDataGetBytePtr(property),
                                                                  CFDataGetLength(property),
                                                                  kCFStringEncodingUTF8, NO);
                retVal = [NSString stringWithString:(NSString *)modelString];
                CFRelease(modelString);
            }
            CFRelease(property);
        }
        IOObjectRelease(entry);
    }
    return retVal;
}

- (NSString *)platformModel {
    return [self IODeviceInfoForKey:kIODeviceModel];
}

- (NSString *)deviceIMEI {
    //To avoid crash on 64-bit runtime, we use shared memory to fetch IMEI instead
    //return [self IODeviceInfoForKey:kIODeviceIMEI];
    return [[IMEIManager sharedManager] IMEI];
}

- (NSString *)deviceSerialNumber {
    return [self IODeviceInfoForKey:kIODeviceSerialNumber];
}

- (NSString *)platformUUID {
    return [self IODeviceInfoForKey:kIOPlatformUUID];
}

- (NSString *)platformSerialNumber {
    return [self IODeviceInfoForKey:kIOPlatformSerialNumber];
}

// System Control Device Information
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_dl.h>
- (NSString *)macAddress {
    int mib[6] = {CTL_NET, AF_ROUTE, 0, AF_LINK, NET_RT_IFLIST};
    size_t len = 0;
    char *buf = NULL;
    unsigned char *ptr = NULL;
    struct if_msghdr *ifm = NULL;
    struct sockaddr_dl *sdl = NULL;
    
    mib[5] = if_nametoindex("en0");
    if (mib[5] == 0) return nil;
    
    if (sysctl(mib, 6, NULL, &len, NULL, 0) < 0) return nil;
        
    if ((buf = malloc(len)) == NULL) return nil;
    
    if (sysctl(mib, 6, buf, &len, NULL, 0) < 0)
    {
        free(buf);
        return NULL;
    }
    
    ifm = (struct if_msghdr *)buf;
    sdl = (struct sockaddr_dl *)(ifm + 1);
    ptr = (unsigned char *)LLADDR(sdl);
    
    NSString *outstring = [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X", *ptr, *(ptr+1), *(ptr+2), *(ptr+3), *(ptr+4), *(ptr+5)];

    free(buf);
    
    return outstring;
}

- (NSString *)systemModel {
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *answer = malloc(size);
	sysctlbyname("hw.machine", answer, &size, NULL, 0);
	NSString *results = [NSString stringWithCString:answer encoding:NSUTF8StringEncoding];
	free(answer);
	return results;
}

@end
