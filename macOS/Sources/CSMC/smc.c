#include "smc.h"

#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

// Структури протоколу AppleSMC (розмір і вирівнювання мають збігатися з драйвером)
typedef struct { char major; char minor; char build; char reserved[1]; UInt16 release; } SMCVers;
typedef struct { UInt16 version; UInt16 length; UInt32 cpuPLimit; UInt32 gpuPLimit; UInt32 memPLimit; } SMCPLimit;
typedef struct { UInt32 dataSize; UInt32 dataType; char dataAttributes; } SMCKeyInfo;
typedef struct {
    UInt32 key;
    SMCVers vers;
    SMCPLimit pLimitData;
    SMCKeyInfo keyInfo;
    char result;
    char status;
    char data8;
    UInt32 data32;
    unsigned char bytes[32];
} SMCParam;

enum { KERNEL_INDEX_SMC = 2, CMD_READ_BYTES = 5, CMD_WRITE_BYTES = 6, CMD_READ_KEYINFO = 9 };

static io_connect_t g_conn = 0;

static UInt32 key4(const char *k) {
    return ((UInt32)(unsigned char)k[0] << 24) | ((UInt32)(unsigned char)k[1] << 16) |
           ((UInt32)(unsigned char)k[2] << 8) | (UInt32)(unsigned char)k[3];
}

static int same_type(UInt32 t, const char *s) { return t == key4(s); }

int smc_open(void) {
    if (g_conn) return 0;
    io_service_t svc = IOServiceGetMatchingService(MACH_PORT_NULL, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t r = IOServiceOpen(svc, mach_task_self(), 0, &g_conn);
    IOObjectRelease(svc);
    return r == kIOReturnSuccess ? 0 : -1;
}

void smc_close(void) {
    if (g_conn) { IOServiceClose(g_conn); g_conn = 0; }
}

static int smc_call(SMCParam *in, SMCParam *out) {
    size_t outSize = sizeof(SMCParam);
    kern_return_t r = IOConnectCallStructMethod(g_conn, KERNEL_INDEX_SMC, in, sizeof(SMCParam), out, &outSize);
    return (r == kIOReturnSuccess && out->result == 0) ? 0 : -1;
}

static int smc_key_info(const char *key, SMCKeyInfo *info) {
    if (smc_open() != 0) return -1;
    SMCParam in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = key4(key);
    in.data8 = CMD_READ_KEYINFO;
    if (smc_call(&in, &out) != 0) return -1;
    *info = out.keyInfo;
    return 0;
}

static int smc_read_raw(const char *key, unsigned char *buf, SMCKeyInfo *info) {
    if (smc_key_info(key, info) != 0) return -1;
    SMCParam in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = key4(key);
    in.keyInfo.dataSize = info->dataSize;
    in.data8 = CMD_READ_BYTES;
    if (smc_call(&in, &out) != 0) return -1;
    memcpy(buf, out.bytes, info->dataSize > 32 ? 32 : info->dataSize);
    return 0;
}

int smc_read_number(const char *key, double *outv) {
    unsigned char b[32] = {0};
    SMCKeyInfo info;
    if (smc_read_raw(key, b, &info) != 0) return -1;
    UInt32 t = info.dataType;

    if (same_type(t, "flt ") && info.dataSize == 4) { float f; memcpy(&f, b, 4); *outv = f; return 0; }
    if (same_type(t, "fpe2")) { *outv = (double)((b[0] << 8) | b[1]) / 4.0; return 0; }
    if (same_type(t, "sp78")) { *outv = (double)(int16_t)((b[0] << 8) | b[1]) / 256.0; return 0; }
    if (same_type(t, "ui8 ")) { *outv = b[0]; return 0; }
    if (same_type(t, "ui16")) { *outv = (double)((b[0] << 8) | b[1]); return 0; }
    if (same_type(t, "ui32")) { *outv = (double)(((UInt32)b[0] << 24) | ((UInt32)b[1] << 16) | ((UInt32)b[2] << 8) | b[3]); return 0; }
    return -1;
}

int smc_write_number(const char *key, double v) {
    SMCKeyInfo info;
    if (smc_key_info(key, &info) != 0) return -1;
    SMCParam in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = key4(key);
    in.data8 = CMD_WRITE_BYTES;
    in.keyInfo.dataSize = info.dataSize;
    UInt32 t = info.dataType;

    if (same_type(t, "flt ")) { float f = (float)v; memcpy(in.bytes, &f, 4); }
    else if (same_type(t, "fpe2")) { UInt16 r = (UInt16)(v * 4.0); in.bytes[0] = r >> 8; in.bytes[1] = r & 0xFF; }
    else if (same_type(t, "ui8 ")) { in.bytes[0] = (unsigned char)v; }
    else if (same_type(t, "ui16")) { UInt16 r = (UInt16)v; in.bytes[0] = r >> 8; in.bytes[1] = r & 0xFF; }
    else if (same_type(t, "ui32")) { UInt32 r = (UInt32)v; in.bytes[0] = r >> 24; in.bytes[1] = (r >> 16) & 0xFF; in.bytes[2] = (r >> 8) & 0xFF; in.bytes[3] = r & 0xFF; }
    else return -1;

    return smc_call(&in, &out);
}

int smc_fan_count(void) {
    double n = 0;
    return smc_read_number("FNum", &n) == 0 ? (int)n : 0;
}

int smc_fan_set_manual(int fan, int manual) {
    char key[5];
    snprintf(key, sizeof key, "F%dMd", fan);
    double cur;
    if (smc_read_number(key, &cur) == 0) {
        if (smc_write_number(key, manual ? 1 : 0) == 0) return 0;
        // Apple Silicon: перед ручним режимом потрібно розблокувати "Ftst"
        if (manual && smc_write_number("Ftst", 1) == 0) {
            for (int i = 0; i < 20; i++) {           // до ~2 с, поки SMC прийме режим
                usleep(100000);
                if (smc_write_number(key, 1) == 0) return 0;
            }
        }
        return -1;
    }
    // Старі Intel Mac: бітова маска "FS! "
    double mask;
    if (smc_read_number("FS! ", &mask) != 0) return -1;
    UInt16 m = (UInt16)mask;
    m = manual ? (m | (1 << fan)) : (m & ~(1 << fan));
    return smc_write_number("FS! ", m);
}

int smc_fan_set_target(int fan, double rpm) {
    char key[5];
    snprintf(key, sizeof key, "F%dTg", fan);
    return smc_write_number(key, rpm);
}

double smc_max_temp(const char *const *keys, int count) {
    double best = -1;
    for (int i = 0; i < count; i++) {
        double v;
        if (smc_read_number(keys[i], &v) == 0 && v > 5 && v < 125 && v > best) best = v;
    }
    return best;
}
