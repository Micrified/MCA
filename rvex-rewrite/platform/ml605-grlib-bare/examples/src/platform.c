
#include "platform.h"
#include "rvex.h"

/******************************************************************************/
/* COMMON                                                                     */
/******************************************************************************/

void _stop(void);
int putchar(int character)        { plat_serial_putc(0, character); return 0; }
int puts(const char *str)         { plat_serial_puts(0, str);       return 0; }
int putd(int value)               { plat_serial_putd(0, str);       return 0; }
int putx(int value)               { plat_serial_putx(0, str);       return 0; }
int rvex_succeed(const char *str) { plat_serial_puts(0, str);       _stop(); }
int rvex_fail(const char *str)    { plat_serial_puts(0, str);       _stop(); }


/******************************************************************************/
/* INTERRUPTS                                                                 */
/******************************************************************************/

#define IRQ_COUNT 32
#define CTXT_COUNT 32

static void (*volatile irq_handlers[CTXT_COUNT * IRQ_COUNT])(unsigned long data);
static unsigned long irq_handlers_data[CTXT_COUNT * IRQ_COUNT];

/**
 * Interrupt callback from startup.
 */
void interrupt(int irq) {
  
  // Unpack the IRQ data.
  int idx = irq & 0x1F;
  int level = irq & 0x3F;
  int core = (irq >> 10) & 0x1F;
  int h = core * IRQ_COUNT + idx;
  void (*handler)(unsigned long data) = irq_handlers[h];
  
  // Continue processing if there is a handler.
  if (handler) {
    
    // Read the current interrupt level and set the new level. This allows the
    // handler to re-enable interrupts safely if nesting is enabled in
    // hardware; higher-priority interrupts will then nest.
    int prev_level = PLAT_IRQCTRL->level;
    PLAT_IRQCTRL->level = level;
    
    // Run the interrupt handler.
    handler(irq_handlers_data[h]);
    
    // Make sure interrupts are disabled, then restore the interrupt level.
    CR_CCR = CR_CCR_IEN_C;
    PLAT_IRQCTRL->level = prev_level;
    
  }
}

/**
 * Registers the specified interrupt handler function for the specified IRQ.
 * Only one handler can be registered at a time.
 */
void plat_irq_register(
  int irq,
  void (*handler)(unsigned long data),
  unsigned long data
) {
  int h = CR_CID * IRQ_COUNT + irq;
  irq_handlers[h] = handler;
  irq_handlers_data[h] = data;
}

/**
 * Enables or masks an interrupt.
 */
void plat_irq_enable(int irq, int enable) {
  // TODO: need to modify the hardware such that COID specifies the context
  // offset, not the lane group offset as it currently does. Then COID + CID
  // specifies the interrupt controller index. Otherwise we can't know which
  // register to access here.
}

/**
 * Returns whether the specified interrupt is pending.
 */
int plat_irq_ispending(int irq) {
  // TODO, see above.
}

/**
 * Clears a pending interrupt.
 */
void plat_irq_clear(int irq) {
  // TODO, see above.
}

/**
 * Forces the specified interrupt on the specified context.
 */
void plat_irq_force(int irq, int context) {
  // TODO, see above.
}


/******************************************************************************/
/* SERIAL PORTS                                                               */
/******************************************************************************/

/**
 * Writes a character to the specified serial port. Blocking.
 */
void plat_serial_putc(int iface, char c) {
  
  if (iface == 0) {
    
#ifndef SIM
    // Wait for the TX data FIFO ready flag.
    while (!(PLAT_DEBUGUART_STAT & (1 << 1)));
#endif
    
    // Write to the UART.
    PLAT_DEBUGUART_DATA = c;
    
  }
}

/**
 * Writes a null-terminated string to the specified serial port. Blocking.
 */
void plat_serial_puts(int iface, const char *s) {
  while (*s) {
    plat_serial_putc(iface, (int)(*s++));
  }
}

/**
 * Writes a 32-bit hexadecimal value to the specified serial port. Blocking.
 */
void plat_serial_putx(int iface, int value) {
  unsigned int val = (unsigned int)value;
  int i;
  char c;
  
  plat_serial_putc(iface, '0');
  plat_serial_putc(iface, 'x');
  for (i = 0; i < 8; i++) {
    c = (char)(val >> 28);
    c = (c < 10) ? ('0' + c) : ('A' + c - 10);
    plat_serial_putc(iface, c);
    val <<= 4;
  }
  
}

/**
 * Writes a 32-bit signed decimal value to the specified serial port. Blocking.
 */
void plat_serial_putd(int iface, int value) {
  unsigned int val;
  int i;
  char c;
  static const int decades[10] = {
    1000000000,
    100000000,
    10000000,
    1000000,
    100000,
    10000,
    1000,
    100,
    10,
    1
  };
  
  // Handle negative numbers.
  if (value < 0) {
    plat_serial_putc(iface, '-');
    value = -value;
  }
  val = (unsigned int)value;
  
  // Divisions are really slow, so let's do without.
  c = '0';
  for (i = 0; i < 10; i++) {
    int dec = decades[i];
    if (val >= dec) {
      break;
    }
  }
  if (i == 10) {
    plat_serial_putc(iface, '0');
  } else {
    for (; i < 10; i++) {
      int dec = decades[i];
      c = '0';
      if (val >= (dec<<3)) { val -= (dec<<3); c += 8; }
      if (val >= (dec<<2)) { val -= (dec<<2); c += 4; }
      if (val >= (dec<<1)) { val -= (dec<<1); c += 2; }
      if (val >= (dec<<0)) { val -= (dec<<0); c += 1; }
      plat_serial_putc(iface, c);
    }
  }
  
}

/**
 * Writes a data buffer to the specified serial port. Non-blocking, same
 * interface as POSIX write.
 */
int plat_serial_write(int iface, const void *buf, int count) {
  const char *cbuf = (const char*)buf;
  int res = 0;
  if (iface == 0) {
    while (count) {
      
      // Stop if the TX data FIFO ready flag is not set.
      if (!(PLAT_DEBUGUART_STAT & (1 << 1))) {
        break;
      }
      
      // Write the next character.
      PLAT_DEBUGUART_DATA = *cbuf++;
      count -= 1;
      res += 1;
      
    }
  } else {
    res = -1;
  }
  return res;
}

/**
 * Reads from the specified serial port into the data buffer. Non-blocking, same
 * interface as POSIX read.
 */
int plat_serial_read(int iface, void *buf, int count) {
  char *cbuf = (char*)buf;
  int res = 0;
  if (iface == 0) {
    while (count) {
      
      // Stop if the RX data FIFO ready flag is not set.
      if (!(PLAT_DEBUGUART_STAT & (1 << 3))) {
        break;
      }
      
      // Read the next character.
      *cbuf++ = PLAT_DEBUGUART_DATA;
      count -= 1;
      res += 1;
      
    }
  } else {
    res = -1;
  }
  return res;
}


