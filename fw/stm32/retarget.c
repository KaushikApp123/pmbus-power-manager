/* Send printf output to USART2 (ST-LINK virtual COM port on Nucleo-64 boards). */
#include "main.h"

extern UART_HandleTypeDef huart2;

int _write(int fd, char *ptr, int len)
{
    (void)fd;
    HAL_UART_Transmit(&huart2, (uint8_t *)ptr, (uint16_t)len, HAL_MAX_DELAY);
    return len;
}
