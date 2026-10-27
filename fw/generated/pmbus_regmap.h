/* AUTO-GENERATED from regmap.yaml by gen/gen_regmap.py. Do not edit. */
#ifndef PMBUS_REGMAP_H
#define PMBUS_REGMAP_H

#include <stdint.h>

#define PMBUS_DEFAULT_ADDR      0x40u
#define PMBUS_VOUT_EXPONENT     (-9)

/* Command codes */
#define PMBUS_OPERATION                0x01u
#define PMBUS_CLEAR_FAULTS             0x03u
#define PMBUS_WRITE_PROTECT            0x10u
#define PMBUS_CAPABILITY               0x19u
#define PMBUS_VOUT_MODE                0x20u
#define PMBUS_VOUT_COMMAND             0x21u
#define PMBUS_VOUT_OV_FAULT_LIMIT      0x40u
#define PMBUS_VOUT_OV_FAULT_RESPONSE   0x41u
#define PMBUS_VOUT_OV_WARN_LIMIT       0x42u
#define PMBUS_VOUT_UV_WARN_LIMIT       0x43u
#define PMBUS_VOUT_UV_FAULT_LIMIT      0x44u
#define PMBUS_VOUT_UV_FAULT_RESPONSE   0x45u
#define PMBUS_STATUS_BYTE              0x78u
#define PMBUS_STATUS_WORD              0x79u
#define PMBUS_STATUS_VOUT              0x7Au
#define PMBUS_STATUS_CML               0x7Eu
#define PMBUS_READ_VOUT                0x8Bu
#define PMBUS_PMBUS_REVISION           0x98u
#define PMBUS_MFR_SIM_VOUT             0xD0u

/* Reset / constant values */
#define PMBUS_RST_OPERATION            0x00u
#define PMBUS_RST_WRITE_PROTECT        0x00u
#define PMBUS_RST_CAPABILITY           0xB0u
#define PMBUS_RST_VOUT_MODE            0x17u
#define PMBUS_RST_VOUT_COMMAND         0x0699u
#define PMBUS_RST_VOUT_OV_FAULT_LIMIT  0x0742u
#define PMBUS_RST_VOUT_OV_FAULT_RESPONSE 0x80u
#define PMBUS_RST_VOUT_OV_WARN_LIMIT   0x06EEu
#define PMBUS_RST_VOUT_UV_WARN_LIMIT   0x0645u
#define PMBUS_RST_VOUT_UV_FAULT_LIMIT  0x05F0u
#define PMBUS_RST_VOUT_UV_FAULT_RESPONSE 0x80u
#define PMBUS_RST_PMBUS_REVISION       0x33u
#define PMBUS_RST_MFR_SIM_VOUT         0x0000u

typedef enum {
    PMBUS_ACC_RW = 0,
    PMBUS_ACC_RO_CONST = 1,
    PMBUS_ACC_RO_HW = 2,
    PMBUS_ACC_W1C_HW = 3,
    PMBUS_ACC_SEND = 4
} pmbus_access_t;

typedef struct {
    const char *name;
    uint8_t code;
    uint8_t size;           /* data bytes */
    pmbus_access_t access;
    uint16_t reset;
} pmbus_reg_info_t;

#define PMBUS_NUM_REGS 19u

static const pmbus_reg_info_t pmbus_regs[PMBUS_NUM_REGS] = {
    { "OPERATION", 0x01u, 1u, PMBUS_ACC_RW, 0x0000u },
    { "CLEAR_FAULTS", 0x03u, 0u, PMBUS_ACC_SEND, 0x0000u },
    { "WRITE_PROTECT", 0x10u, 1u, PMBUS_ACC_RW, 0x0000u },
    { "CAPABILITY", 0x19u, 1u, PMBUS_ACC_RO_CONST, 0x00B0u },
    { "VOUT_MODE", 0x20u, 1u, PMBUS_ACC_RO_CONST, 0x0017u },
    { "VOUT_COMMAND", 0x21u, 2u, PMBUS_ACC_RW, 0x0699u },
    { "VOUT_OV_FAULT_LIMIT", 0x40u, 2u, PMBUS_ACC_RW, 0x0742u },
    { "VOUT_OV_FAULT_RESPONSE", 0x41u, 1u, PMBUS_ACC_RW, 0x0080u },
    { "VOUT_OV_WARN_LIMIT", 0x42u, 2u, PMBUS_ACC_RW, 0x06EEu },
    { "VOUT_UV_WARN_LIMIT", 0x43u, 2u, PMBUS_ACC_RW, 0x0645u },
    { "VOUT_UV_FAULT_LIMIT", 0x44u, 2u, PMBUS_ACC_RW, 0x05F0u },
    { "VOUT_UV_FAULT_RESPONSE", 0x45u, 1u, PMBUS_ACC_RW, 0x0080u },
    { "STATUS_BYTE", 0x78u, 1u, PMBUS_ACC_RO_HW, 0x0000u },
    { "STATUS_WORD", 0x79u, 2u, PMBUS_ACC_RO_HW, 0x0000u },
    { "STATUS_VOUT", 0x7Au, 1u, PMBUS_ACC_W1C_HW, 0x0000u },
    { "STATUS_CML", 0x7Eu, 1u, PMBUS_ACC_W1C_HW, 0x0000u },
    { "READ_VOUT", 0x8Bu, 2u, PMBUS_ACC_RO_HW, 0x0000u },
    { "PMBUS_REVISION", 0x98u, 1u, PMBUS_ACC_RO_CONST, 0x0033u },
    { "MFR_SIM_VOUT", 0xD0u, 2u, PMBUS_ACC_RW, 0x0000u },
};

/* LINEAR16 helpers: millivolts <-> register value */
static inline uint16_t pmbus_mv_to_linear16(uint32_t mv)
{
    return (uint16_t)(((mv << 9) + 500u) / 1000u);
}

static inline uint32_t pmbus_linear16_to_mv(uint16_t v)
{
    return ((uint32_t)v * 1000u + (1u << 8)) >> 9;
}

#endif /* PMBUS_REGMAP_H */
