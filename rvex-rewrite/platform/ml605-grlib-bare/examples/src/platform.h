// platform TODO:
//  - IDF -> 0
//  - 4 timers instead of 3
//  - PMbus I2C for power measurement?
//  - gracectrl?
//  - serial port using the SMAs and a serial port using the remaning display
//    pins?

#ifndef _PLATFORM_H_
#define _PLATFORM_H_

/******************************************************************************/
/* COMMON                                                                     */
/******************************************************************************/

/**
 * This function initializes the platform and should be called at the start of
 * the main().
 */
void plat_init(void);

// Debugging stuff needed by start.o. These use serial port 0 (the debug port).
int putchar(int character);
int puts(const char *str);
int rvex_succeed(const char *str);
int rvex_fail(const char *str);


/******************************************************************************/
/* INTERRUPTS                                                                 */
/******************************************************************************/

// Interrupt controller interface.
typedef struct {
  unsigned int brbro;
  unsigned int rvect;
  unsigned int level;
  unsigned int prio;
  unsigned int ena;
  unsigned int disa;
  unsigned int pend;
  unsigned int clear;
} irqctrl_ctxt_t;

typedef struct {
  unsigned int done;
  unsigned int idle;
  unsigned int brk;
  unsigned int caps;
  unsigned int RESERVED_A[2];
  unsigned int period;
  unsigned int time;
  unsigned int RESERVED_B[248];
  irqctrl_ctxt_t c[31];
} irqctrl_t;

#define PLAT_IRQCTRL ((volatile irqmp_t*)0xD2000000)

// Interrupt sources.
#define IRQ_TICK      1
#define IRQ_DBG_UART  2

/**
 * Registers the specified interrupt handler function for the specified IRQ.
 * Only one handler can be registered at a time. data is passed to the handler.
 */
void plat_irq_register(
  int irq,
  void (*handler)(unsigned long data),
  unsigned long data
);

/**
 * Enables or masks an interrupt.
 */
void plat_irq_enable(int irq, int enable);

/**
 * Returns whether the specified interrupt is pending.
 */
int plat_irq_ispending(int irq);

/**
 * Clears a pending interrupt.
 */
void plat_irq_clear(int irq);

/**
 * Forces the specified interrupt on the specified context.
 */
void plat_irq_force(int irq, int context);


/******************************************************************************/
/* SERIAL PORTS                                                               */
/******************************************************************************/

// r-VEX debug UART peripheral.
#define PLAT_DEBUGUART_DATA (*((volatile unsigned char *)(0xD1000000)))
#define PLAT_DEBUGUART_STAT (*((volatile unsigned char *)(0xD1000004)))
#define PLAT_DEBUGUART_CTRL (*((volatile unsigned char *)(0xD1000008)))

#define PLAT_NUM_SERIAL 1

/**
 * Writes a character to the specified serial port. Blocking.
 */
void plat_serial_putc(int iface, char c);

/**
 * Writes a null-terminated string to the specified serial port. Blocking.
 */
void plat_serial_puts(int iface, const char *s);

/**
 * Writes a 32-bit hexadecimal value to the specified serial port. Blocking.
 */
void plat_serial_putx(int iface, int value);

/**
 * Writes a 32-bit signed decimal value to the specified serial port. Blocking.
 */
void plat_serial_putd(int iface, int value);

/**
 * Writes a data buffer to the specified serial port. Non-blocking, same
 * interface as POSIX write.
 */
int plat_serial_write(int iface, const void *buf, int count);

/**
 * Reads from the specified serial port into the data buffer. Non-blocking, same
 * interface as POSIX read.
 */
int plat_serial_read(int iface, void *buf, int count);


#endif
