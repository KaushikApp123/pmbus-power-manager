/*
 * Hardware test sequence for the PMBus Power Manager on the UPduino.
 * Call pmbus_demo_run(&hi2c1) from main() after MX_I2C1_Init().
 * Results print over printf (retarget to the ST-LINK virtual COM port,
 * see retarget.c).
 *
 * Optional GPIO checks: wire the FPGA's EN, PG and SMBALERT# pins to the
 * STM32 and set the PMBUS_DEMO_* pin macros below. Define
 * PMBUS_DEMO_NO_GPIO to skip pin checks.
 */
#include <stdio.h>

#include "pmbus_host.h"
#include "../generated/pmbus_regmap.h"

#ifndef PMBUS_DEMO_NO_GPIO
/* Nucleo-64 Arduino header A0, A1, A2 */
#define EN_PORT     GPIOA
#define EN_PIN      GPIO_PIN_0
#define PG_PORT     GPIOA
#define PG_PIN      GPIO_PIN_1
#define ALERT_PORT  GPIOA
#define ALERT_PIN   GPIO_PIN_4
#define PIN(p, n)   (HAL_GPIO_ReadPin((p), (n)) == GPIO_PIN_SET)
#endif

static int n_pass, n_fail;

static void result(bool ok, const char *what)
{
    if (ok) n_pass++; else n_fail++;
    printf("[%s] %s\r\n", ok ? "PASS" : "FAIL", what);
}

static void check_pins(bool en, bool pg, bool alert_n, const char *what)
{
#ifndef PMBUS_DEMO_NO_GPIO
    char msg[96];
    bool ok = PIN(EN_PORT, EN_PIN) == en && PIN(PG_PORT, PG_PIN) == pg &&
              PIN(ALERT_PORT, ALERT_PIN) == alert_n;
    snprintf(msg, sizeof msg, "%s: pins EN=%d PG=%d ALERT#=%d", what,
             PIN(EN_PORT, EN_PIN), PIN(PG_PORT, PG_PIN), PIN(ALERT_PORT, ALERT_PIN));
    result(ok, msg);
#else
    (void)en; (void)pg; (void)alert_n; (void)what;
#endif
}

static uint16_t rd(pmbus_dev_t *d, uint8_t cmd, uint8_t size)
{
    uint8_t b = 0;
    uint16_t w = 0;
    pmbus_status_t s = (size == 2) ? pmbus_read_word(d, cmd, &w) : pmbus_read_byte(d, cmd, &b);
    if (s != PMBUS_OK)
        printf("  read 0x%02X failed: %s\r\n", cmd, pmbus_status_str(s));
    return (size == 2) ? w : b;
}

static void expect(pmbus_dev_t *d, uint8_t cmd, uint8_t size, uint16_t exp, const char *what)
{
    char msg[96];
    uint16_t v = rd(d, cmd, size);
    snprintf(msg, sizeof msg, "%s: 0x%02X = 0x%04X (expect 0x%04X)", what, cmd, v, exp);
    result(v == exp, msg);
}

/* Read STATUS_CML, compare, then clear it */
static void expect_cml(pmbus_dev_t *d, uint8_t exp, const char *what)
{
    expect(d, PMBUS_STATUS_CML, 1, exp, what);
    pmbus_write_byte(d, PMBUS_STATUS_CML, 0xFF);
}

static void power_cycle(pmbus_dev_t *d)
{
    pmbus_write_byte(d, PMBUS_OPERATION, 0x00);
    pmbus_send_byte(d, PMBUS_CLEAR_FAULTS);
    pmbus_write_byte(d, PMBUS_OPERATION, 0x80);
    HAL_Delay(100);   /* ramp (~14 ms) + 32 ms blanking + margin */
}

void pmbus_demo_run(I2C_HandleTypeDef *hi2c)
{
    pmbus_dev_t dev = { .hi2c = hi2c, .addr7 = PMBUS_DEFAULT_ADDR, .use_pec = true, .timeout_ms = 10 };
    pmbus_dev_t *d = &dev;
    char msg[96];
    n_pass = n_fail = 0;

    printf("\r\n=== PMBus Power Manager hardware test ===\r\n");

    /* --- Identity and register dump ------------------------------------- */
    expect(d, PMBUS_PMBUS_REVISION, 1, PMBUS_RST_PMBUS_REVISION, "PMBUS_REVISION");
    expect(d, PMBUS_CAPABILITY, 1, PMBUS_RST_CAPABILITY, "CAPABILITY");
    expect(d, PMBUS_VOUT_MODE, 1, PMBUS_RST_VOUT_MODE, "VOUT_MODE");
    printf("Register dump (PEC on):\r\n");
    for (unsigned i = 0; i < PMBUS_NUM_REGS; i++) {
        const pmbus_reg_info_t *r = &pmbus_regs[i];
        if (r->access == PMBUS_ACC_SEND)
            continue;
        printf("  0x%02X %-24s 0x%04X\r\n", r->code, r->name, rd(d, r->code, r->size));
    }

    /* --- Bus behaviour --------------------------------------------------- */
    pmbus_write_byte(d, PMBUS_STATUS_CML, 0xFF);
    pmbus_write_word(d, PMBUS_VOUT_COMMAND, pmbus_mv_to_linear16(3300));
    expect(d, PMBUS_VOUT_COMMAND, 2, pmbus_mv_to_linear16(3300), "VOUT_COMMAND write+PEC");

    pmbus_write_word_bad_pec(d, PMBUS_VOUT_COMMAND, pmbus_mv_to_linear16(5000));
    expect(d, PMBUS_VOUT_COMMAND, 2, pmbus_mv_to_linear16(3300), "bad PEC write ignored");
    expect_cml(d, 0x20, "bad PEC flagged");

    /* 4 data bytes: not a word, not a word + PEC */
    { uint8_t junk[4] = { 0x11, 0x22, 0x33, 0x44 };
      pmbus_write_raw(d, PMBUS_VOUT_COMMAND, junk, 4); }
    expect(d, PMBUS_VOUT_COMMAND, 2, pmbus_mv_to_linear16(3300), "4-byte write ignored");
    expect_cml(d, 0x40, "bad length flagged");

    pmbus_write_byte(d, 0xE5, 0x00);
    expect_cml(d, 0x80, "unsupported command flagged");

    pmbus_write_byte(d, PMBUS_READ_VOUT, 0x00);
    expect_cml(d, 0x80, "write to read-only flagged");

    pmbus_write_byte(d, PMBUS_OPERATION, 0x81);
    expect_cml(d, 0x40, "illegal OPERATION value flagged");

    {
        pmbus_dev_t other = dev;
        other.addr7 = PMBUS_DEFAULT_ADDR ^ 0x01;
        uint8_t v;
        result(pmbus_read_byte(&other, PMBUS_PMBUS_REVISION, &v) == PMBUS_NACK, "wrong address NACKed");
    }

    {
        int bad = 0;
        uint8_t v;
        for (int i = 0; i < 1000; i++)
            if (pmbus_read_byte(d, PMBUS_PMBUS_REVISION, &v) != PMBUS_OK || v != PMBUS_RST_PMBUS_REVISION)
                bad++;
        snprintf(msg, sizeof msg, "1000 back-to-back reads with PEC, %d errors", bad);
        result(bad == 0, msg);
    }

    /* --- Power up -------------------------------------------------------- */
    power_cycle(d);
    expect(d, PMBUS_STATUS_WORD, 2, 0x0000, "powered, all good");
    {
        uint16_t v = rd(d, PMBUS_READ_VOUT, 2);
        unsigned mv = (unsigned)pmbus_linear16_to_mv(v);
        snprintf(msg, sizeof msg, "READ_VOUT = %u mV", mv);
        result(mv > 3250 && mv < 3350, msg);
    }
    check_pins(true, true, true, "on");

    /* --- OV fault, latch off, recover ----------------------------------- */
    pmbus_write_word(d, PMBUS_MFR_SIM_VOUT, pmbus_mv_to_linear16(4000));
    HAL_Delay(20);
    expect(d, PMBUS_STATUS_VOUT, 1, 0xC0, "OV fault + warn");
    expect(d, PMBUS_STATUS_BYTE, 1, 0x61, "OFF + VOUT_OV + other");
    check_pins(false, false, false, "OV fault");
    pmbus_write_word(d, PMBUS_MFR_SIM_VOUT, 0);
    HAL_Delay(50);    /* plant ramps down below the OV limits first */
    pmbus_send_byte(d, PMBUS_CLEAR_FAULTS);
    HAL_Delay(5);
    expect(d, PMBUS_STATUS_BYTE, 1, 0x40, "still latched off after CLEAR_FAULTS");
    check_pins(false, false, true, "latched, alert released");
    power_cycle(d);
    expect(d, PMBUS_STATUS_WORD, 2, 0x0000, "recovered after OPERATION off/on");
    check_pins(true, true, true, "recovered");

    /* --- UV fault -------------------------------------------------------- */
    pmbus_write_word(d, PMBUS_MFR_SIM_VOUT, pmbus_mv_to_linear16(2500));
    HAL_Delay(20);
    expect(d, PMBUS_STATUS_VOUT, 1, 0x30, "UV fault + warn");
    check_pins(false, false, false, "UV fault");
    pmbus_write_word(d, PMBUS_MFR_SIM_VOUT, 0);
    power_cycle(d);

    /* --- Hiccup mode: watch EN toggle on the logic analyzer --------------- */
    pmbus_write_byte(d, PMBUS_VOUT_UV_FAULT_RESPONSE, 0xC0);
    pmbus_write_word(d, PMBUS_MFR_SIM_VOUT, pmbus_mv_to_linear16(2500));
#ifndef PMBUS_DEMO_NO_GPIO
    {
        int rises = 0;
        bool prev = PIN(EN_PORT, EN_PIN);
        uint32_t t0 = HAL_GetTick();
        while (HAL_GetTick() - t0 < 1000) {
            bool now = PIN(EN_PORT, EN_PIN);
            if (now && !prev) rises++;
            prev = now;
        }
        snprintf(msg, sizeof msg, "hiccup: %d restarts in 1 s (expect ~7)", rises);
        result(rises >= 5 && rises <= 9, msg);
    }
#else
    HAL_Delay(1000);
#endif
    pmbus_write_word(d, PMBUS_MFR_SIM_VOUT, 0);
    HAL_Delay(200);
    pmbus_send_byte(d, PMBUS_CLEAR_FAULTS);
    expect(d, PMBUS_STATUS_WORD, 2, 0x0000, "hiccup recovered");
    pmbus_write_byte(d, PMBUS_VOUT_UV_FAULT_RESPONSE, 0x80);

    /* --- Write protect --------------------------------------------------- */
    pmbus_write_byte(d, PMBUS_WRITE_PROTECT, 0x80);
    pmbus_write_word(d, PMBUS_VOUT_COMMAND, pmbus_mv_to_linear16(1800));
    expect(d, PMBUS_VOUT_COMMAND, 2, pmbus_mv_to_linear16(3300), "WP 0x80 blocks VOUT_COMMAND");
    pmbus_write_byte(d, PMBUS_WRITE_PROTECT, 0x00);
    expect_cml(d, 0x40, "WP violation flagged");

    /* --- Done ------------------------------------------------------------ */
    pmbus_write_byte(d, PMBUS_OPERATION, 0x00);
    printf("=== %d passed, %d failed ===\r\n", n_pass, n_fail);
}
