/*
 * Minimal PMBus host on top of the STM32 HAL I2C driver.
 * Works on any STM32 family with HAL_I2C_Master_Transmit / HAL_I2C_Mem_Read.
 */
#ifndef PMBUS_HOST_H
#define PMBUS_HOST_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "main.h"   /* CubeMX header, pulls in the right stm32xxxx_hal.h */

typedef struct {
    I2C_HandleTypeDef *hi2c;
    uint8_t  addr7;        /* 7-bit target address */
    bool     use_pec;      /* append / check PEC on every transaction */
    uint32_t timeout_ms;
} pmbus_dev_t;

typedef enum {
    PMBUS_OK = 0,
    PMBUS_NACK,            /* HAL error: address or data not acknowledged */
    PMBUS_PEC_MISMATCH,    /* read PEC did not match */
    PMBUS_BUS_ERROR
} pmbus_status_t;

uint8_t pmbus_crc8(uint8_t crc, const uint8_t *data, size_t len);

pmbus_status_t pmbus_send_byte(pmbus_dev_t *dev, uint8_t cmd);
pmbus_status_t pmbus_write_byte(pmbus_dev_t *dev, uint8_t cmd, uint8_t value);
pmbus_status_t pmbus_write_word(pmbus_dev_t *dev, uint8_t cmd, uint16_t value);
pmbus_status_t pmbus_read_byte(pmbus_dev_t *dev, uint8_t cmd, uint8_t *value);
pmbus_status_t pmbus_read_word(pmbus_dev_t *dev, uint8_t cmd, uint16_t *value);

/* Fault injection: send cmd plus raw bytes exactly as given (no PEC added). */
pmbus_status_t pmbus_write_raw(pmbus_dev_t *dev, uint8_t cmd, const uint8_t *data, size_t len);
/* Same as a normal write but with a deliberately corrupted PEC byte. */
pmbus_status_t pmbus_write_word_bad_pec(pmbus_dev_t *dev, uint8_t cmd, uint16_t value);

const char *pmbus_status_str(pmbus_status_t s);

#endif /* PMBUS_HOST_H */
