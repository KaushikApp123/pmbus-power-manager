#include "pmbus_host.h"

#include <string.h>

uint8_t pmbus_crc8(uint8_t crc, const uint8_t *data, size_t len)
{
    while (len--) {
        crc ^= *data++;
        for (int i = 0; i < 8; i++)
            crc = (crc & 0x80u) ? (uint8_t)((crc << 1) ^ 0x07u) : (uint8_t)(crc << 1);
    }
    return crc;
}

static pmbus_status_t from_hal(HAL_StatusTypeDef st, I2C_HandleTypeDef *hi2c)
{
    if (st == HAL_OK)
        return PMBUS_OK;
    if (HAL_I2C_GetError(hi2c) & HAL_I2C_ERROR_AF)
        return PMBUS_NACK;
    return PMBUS_BUS_ERROR;
}

/* buf[0] = cmd, buf[1..n] = data. Adds PEC if enabled (or corrupted on request). */
static pmbus_status_t write_frame(pmbus_dev_t *dev, uint8_t *buf, size_t n, bool pec, bool corrupt)
{
    if (pec) {
        uint8_t a = (uint8_t)(dev->addr7 << 1);
        uint8_t crc = pmbus_crc8(0, &a, 1);
        crc = pmbus_crc8(crc, buf, n);
        buf[n++] = corrupt ? (uint8_t)(crc ^ 0x5Au) : crc;
    }
    HAL_StatusTypeDef st = HAL_I2C_Master_Transmit(dev->hi2c, (uint16_t)(dev->addr7 << 1),
                                                   buf, (uint16_t)n, dev->timeout_ms);
    return from_hal(st, dev->hi2c);
}

static pmbus_status_t read_frame(pmbus_dev_t *dev, uint8_t cmd, uint8_t *out, size_t n)
{
    uint8_t rx[3];
    size_t total = n + (dev->use_pec ? 1u : 0u);

    /* S Addr+W cmd Sr Addr+R data... [PEC] NACK P */
    HAL_StatusTypeDef st = HAL_I2C_Mem_Read(dev->hi2c, (uint16_t)(dev->addr7 << 1), cmd,
                                            I2C_MEMADD_SIZE_8BIT, rx, (uint16_t)total,
                                            dev->timeout_ms);
    pmbus_status_t r = from_hal(st, dev->hi2c);
    if (r != PMBUS_OK)
        return r;

    if (dev->use_pec) {
        uint8_t hdr[3] = { (uint8_t)(dev->addr7 << 1), cmd, (uint8_t)((dev->addr7 << 1) | 1u) };
        uint8_t crc = pmbus_crc8(0, hdr, 3);
        crc = pmbus_crc8(crc, rx, n);
        if (crc != rx[n])
            return PMBUS_PEC_MISMATCH;
    }
    memcpy(out, rx, n);
    return PMBUS_OK;
}

pmbus_status_t pmbus_send_byte(pmbus_dev_t *dev, uint8_t cmd)
{
    uint8_t buf[2] = { cmd };
    return write_frame(dev, buf, 1, dev->use_pec, false);
}

pmbus_status_t pmbus_write_byte(pmbus_dev_t *dev, uint8_t cmd, uint8_t value)
{
    uint8_t buf[3] = { cmd, value };
    return write_frame(dev, buf, 2, dev->use_pec, false);
}

pmbus_status_t pmbus_write_word(pmbus_dev_t *dev, uint8_t cmd, uint16_t value)
{
    uint8_t buf[4] = { cmd, (uint8_t)value, (uint8_t)(value >> 8) };
    return write_frame(dev, buf, 3, dev->use_pec, false);
}

pmbus_status_t pmbus_write_word_bad_pec(pmbus_dev_t *dev, uint8_t cmd, uint16_t value)
{
    uint8_t buf[4] = { cmd, (uint8_t)value, (uint8_t)(value >> 8) };
    return write_frame(dev, buf, 3, true, true);
}

pmbus_status_t pmbus_write_raw(pmbus_dev_t *dev, uint8_t cmd, const uint8_t *data, size_t len)
{
    uint8_t buf[16];
    if (len > sizeof(buf) - 1)
        return PMBUS_BUS_ERROR;
    buf[0] = cmd;
    if (len)
        memcpy(&buf[1], data, len);
    return write_frame(dev, buf, len + 1, false, false);
}

pmbus_status_t pmbus_read_byte(pmbus_dev_t *dev, uint8_t cmd, uint8_t *value)
{
    return read_frame(dev, cmd, value, 1);
}

pmbus_status_t pmbus_read_word(pmbus_dev_t *dev, uint8_t cmd, uint16_t *value)
{
    uint8_t b[2];
    pmbus_status_t r = read_frame(dev, cmd, b, 2);
    if (r == PMBUS_OK)
        *value = (uint16_t)(b[0] | (b[1] << 8));
    return r;
}

const char *pmbus_status_str(pmbus_status_t s)
{
    switch (s) {
    case PMBUS_OK:           return "OK";
    case PMBUS_NACK:         return "NACK";
    case PMBUS_PEC_MISMATCH: return "PEC mismatch";
    default:                 return "bus error";
    }
}
