/* Host-side unit test for the PEC and LINEAR16 helpers: gcc fw/test_host.c -o t && ./t */
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include "generated/pmbus_regmap.h"

static uint8_t crc8(uint8_t crc, const uint8_t *d, size_t n)
{
    while (n--) { crc ^= *d++; for (int i = 0; i < 8; i++) crc = (crc & 0x80) ? (uint8_t)((crc << 1) ^ 7) : (uint8_t)(crc << 1); }
    return crc;
}

int main(void)
{
    int fail = 0;
    const uint8_t chk[] = "123456789";
    fail += crc8(0, chk, 9) != 0xF4;
    fail += pmbus_mv_to_linear16(3300) != 1690;
    fail += pmbus_linear16_to_mv(PMBUS_RST_VOUT_COMMAND) != 3299;
    fail += pmbus_mv_to_linear16(4000) != 0x0800;
    /* PEC appended to a message makes the CRC zero */
    uint8_t m[5] = { PMBUS_DEFAULT_ADDR << 1, PMBUS_VOUT_COMMAND, 0x9A, 0x06, 0 };
    m[4] = crc8(0, m, 4);
    fail += crc8(0, m, 5) != 0;
    printf("%s\n", fail ? "FAIL" : "PASS");
    return fail;
}
