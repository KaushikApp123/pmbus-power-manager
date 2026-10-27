/*
 * Paste into the CubeMX-generated Core/Src/main.c.
 *
 * CubeMX setup (Nucleo-F401RE shown, any STM32 works):
 *   I2C1: Standard or Fast mode (100 or 400 kHz), PB8 = SCL, PB9 = SDA
 *   USART2: 115200 8N1 (already set up on Nucleo boards)
 *   GPIO inputs: PA0 = EN, PA1 = PG, PA4 = SMBALERT# (no pull)
 *   Add fw/stm32/*.c to Core/Src and fw/stm32 + fw/generated to the include path.
 */

/* USER CODE BEGIN Includes */
#include <stdio.h>
void pmbus_demo_run(I2C_HandleTypeDef *hi2c);
/* USER CODE END Includes */

  /* USER CODE BEGIN 2 */
  HAL_Delay(100);              /* let the FPGA finish configuration */
  pmbus_demo_run(&hi2c1);
  /* USER CODE END 2 */
