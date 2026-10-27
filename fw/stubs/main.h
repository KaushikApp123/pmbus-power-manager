/* Minimal HAL stand-in so the firmware compiles on a PC for CI. Not used on target. */
#include <stdint.h>
typedef enum {HAL_OK, HAL_ERROR} HAL_StatusTypeDef;
typedef struct {int x;} I2C_HandleTypeDef;
typedef struct {int x;} UART_HandleTypeDef;
typedef struct {int x;} GPIO_TypeDef;
typedef enum {GPIO_PIN_RESET, GPIO_PIN_SET} GPIO_PinState;
extern GPIO_TypeDef *GPIOA;
#define GPIO_PIN_0 1
#define GPIO_PIN_1 2
#define GPIO_PIN_4 16
#define HAL_I2C_ERROR_AF 4u
#define I2C_MEMADD_SIZE_8BIT 1u
#define HAL_MAX_DELAY 0xFFFFFFFFu
HAL_StatusTypeDef HAL_I2C_Master_Transmit(I2C_HandleTypeDef*, uint16_t, uint8_t*, uint16_t, uint32_t);
HAL_StatusTypeDef HAL_I2C_Mem_Read(I2C_HandleTypeDef*, uint16_t, uint16_t, uint16_t, uint8_t*, uint16_t, uint32_t);
uint32_t HAL_I2C_GetError(I2C_HandleTypeDef*);
HAL_StatusTypeDef HAL_UART_Transmit(UART_HandleTypeDef*, uint8_t*, uint16_t, uint32_t);
GPIO_PinState HAL_GPIO_ReadPin(GPIO_TypeDef*, uint16_t);
void HAL_Delay(uint32_t);
uint32_t HAL_GetTick(void);
