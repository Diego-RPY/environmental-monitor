/* ================================================================
 * lcd2004_counter.S
 * Counts 0 → 10 on a 2004 HD44780 LCD — STM32F401RE (Arduino IDE)
 *
 * .S extension: C preprocessor runs first → #define works here.
 * The Arduino core owns the vector table, startup and clock setup
 * (84 MHz on F401RE), so this file only provides setup() and loop().
 * Place it inside your sketch folder alongside the .ino file.
 *
 * Wiring — all control and data lines on GPIOB (RW tied to GND):
 *
 *   LCD pin          STM32 pin
 *   ──────────────────────────────
 *   1  VSS         → GND
 *   2  VDD         → 5 V
 *   3  V0          → potentiometer wiper (contrast)
 *   4  RS          → PB0
 *   5  RW          → GND  (write-only mode)
 *   6  EN          → PB1
 *   11 D4          → PB4
 *   12 D5          → PB5
 *   13 D6          → PB6
 *   14 D7          → PB7
 *   15 A (backlight)→ 5 V via 100 Ω
 *   16 K (backlight)→ GND
 *
 * The data nibble (D4-D7) maps directly to PB[7:4], so sending
 * nibble N to the LCD is just writing (N << 4) to the port.
 * ================================================================ */

/* ── Peripheral register addresses ── */
#define RCC_AHB1ENR   0x40023830   /* AHB1 peripheral clock register */
#define GPIOB_MODER   0x40020400   /* PB mode register               */
#define GPIOB_BSRR    0x40020418   /* PB bit set/reset register      */

#define GPIOBEN       (1 << 1)     /* AHB1ENR: GPIOB clock enable    */

/* ── GPIO bitmasks (BSRR / ODR lower half) ── */
#define RS_BIT        0x0001       /* PB0 – register select          */
#define EN_BIT        0x0002       /* PB1 – enable strobe            */
/* Data nibble occupies PB[7:4]; no individual defines needed        */

/* Single BSRR write that resets RS, EN, D4-D7 all at once.
 * Bits [31:16] of BSRR are the reset field → drive LOW.
 * PB0|PB1|PB4|PB5|PB6|PB7 = 0xF3 shifted left 16 = 0x00F30000     */
#define LCD_RST       0x00F30000

/* GPIOB_MODER: 2 bits per pin.  Pins PB0,PB1,PB4-PB7.
 *   CLR mask: 0xFF0F  (clears both mode bits for each of the 6 pins)
 *   SET mask: 0x5505  (writes 01 = general-purpose output to each)   */
#define MODER_CLR     0xFF0F
#define MODER_SET     0x5505

/* ── Timing constants (3-cycle spin loop @ 84 MHz ≈ 35.7 ns/iter) ── */
#define T_50MS        1400000      /* power-on wait                  */
#define T_5MS           140000     /* first wake-up delay            */
#define T_1520US         42560     /* clear/home command latency     */
#define T_200US           5600     /* 2nd and 3rd wake-up delays     */
#define T_37US            1050     /* normal command execution time  */
#define T_1S          28000000     /* display hold between digits    */

/* ── HD44780 command bytes ── */
#define CMD_CLEAR     0x01         /* clear display, cursor home     */
#define CMD_ENTRY     0x06         /* cursor right, no shift         */
#define CMD_DISP_ON   0x0C         /* display on, cursor/blink off   */
#define CMD_FUNC      0x28         /* 4-bit bus, 2 lines, 5×8 font  */

/* Cursor position: row 1 (2nd line), column 9.
 * 2004 DDRAM map: row 1 starts at 0x40.
 * → address = 0x40 + 9 = 0x49 → Set DDRAM cmd = 0x80 | 0x49 = 0xC9 */
#define CMD_POS       0xC9

.syntax unified
.cpu cortex-m4
.thumb

.section .text

/* ================================================================
 * setup()  —  called once by the Arduino runtime after boot
 * ================================================================ */
.thumb_func
.global setup
setup:
    push {lr}

    /* 1. Enable GPIOB peripheral clock */
    ldr  r0, =RCC_AHB1ENR
    ldr  r1, [r0]
    orr  r1, r1, #GPIOBEN
    str  r1, [r0]

    /* 2. Configure PB0, PB1, PB4-PB7 as general-purpose outputs.
     *    Read-modify-write to preserve other pins on the same port. */
    ldr  r0, =GPIOB_MODER
    ldr  r1, [r0]
    ldr  r2, =MODER_CLR
    bic  r1, r1, r2             /* clear the 2-bit fields           */
    ldr  r2, =MODER_SET
    orr  r1, r1, r2             /* write output mode (01)           */
    str  r1, [r0]

    /* 3. Drive all six LCD lines low before the display powers up */
    ldr  r0, =GPIOB_BSRR
    ldr  r1, =LCD_RST
    str  r1, [r0]

    /* 4. Wait ≥40 ms for the LCD VDD to stabilise (we use 50 ms) */
    ldr  r0, =T_50MS
    bl   delay

    /* 5. Run the HD44780 4-bit initialisation sequence */
    bl   lcd_init

    pop  {pc}

/* ================================================================
 * loop()  —  counts 0 → 10 on the display and repeats forever.
 *            This function never returns to the Arduino runtime.
 * ================================================================ */
.thumb_func
.global loop
loop:
    push {r4, lr}
    mov  r4, #0                 /* r4 = current count (0 … 10)     */

count_loop:
    /* ── Position cursor at row 1, col 9 ── */
    mov  r0, #CMD_POS
    bl   lcd_cmd

    /* ── Print exactly two characters so old content is overwritten ──
     *    " 0" … " 9"  for single digits
     *    "10"          for ten                                       */
    cmp  r4, #10
    bne  single_digit

    mov  r0, #'1'
    bl   lcd_data
    mov  r0, #'0'
    bl   lcd_data
    b    printed

single_digit:
    mov  r0, #' '               /* leading space keeps layout clean */
    bl   lcd_data
    add  r0, r4, #'0'           /* integer → ASCII digit            */
    bl   lcd_data

printed:
    /* Hold the value on screen for 1 second */
    ldr  r0, =T_1S
    bl   delay

    /* Advance counter; reset to 0 after 10 */
    add  r4, r4, #1
    cmp  r4, #11
    bne  count_loop
    mov  r4, #0
    b    count_loop

/* ================================================================
 * lcd_init  —  HD44780 power-on sequence, 4-bit mode
 *
 * The datasheet requires three 0x3 nibbles at decreasing intervals
 * to reliably wake the controller regardless of power-on state,
 * followed by a 0x2 nibble to commit to 4-bit mode.
 * ================================================================ */
.thumb_func
lcd_init:
    push {lr}

    /* ── Wake-up phase: three 0x3 nibbles ── */
    mov  r0, #0x3
    mov  r1, #0
    bl   lcd_send_nibble
    ldr  r0, =T_5MS
    bl   delay

    mov  r0, #0x3
    mov  r1, #0
    bl   lcd_send_nibble
    ldr  r0, =T_200US
    bl   delay

    mov  r0, #0x3
    mov  r1, #0
    bl   lcd_send_nibble
    ldr  r0, =T_200US
    bl   delay

    /* ── Commit to 4-bit bus mode ── */
    mov  r0, #0x2
    mov  r1, #0
    bl   lcd_send_nibble
    ldr  r0, =T_37US
    bl   delay

    /* ── Configure display (all commands use the 2-nibble path now) ── */
    mov  r0, #CMD_FUNC          /* 4-bit, 2 lines, 5×8 font         */
    bl   lcd_cmd

    mov  r0, #0x08              /* display off                       */
    bl   lcd_cmd

    mov  r0, #CMD_CLEAR         /* clear all DDRAM                   */
    bl   lcd_cmd
    ldr  r0, =T_1520US          /* clear takes ≥1.52 ms to execute  */
    bl   delay

    mov  r0, #CMD_ENTRY         /* cursor increments right           */
    bl   lcd_cmd

    mov  r0, #CMD_DISP_ON       /* display on, no cursor/blink       */
    bl   lcd_cmd

    pop  {pc}

/* ================================================================
 * lcd_cmd  —  send a full command byte to the LCD  (RS = 0)
 * r0 = command byte
 * ================================================================ */
.thumb_func
lcd_cmd:
    push {r4, lr}
    mov  r4, r0                 /* save byte across calls           */

    /* High nibble first */
    lsr  r0, r4, #4
    and  r0, r0, #0xF
    mov  r1, #0                 /* RS = 0: command                  */
    bl   lcd_send_nibble

    /* Then low nibble */
    and  r0, r4, #0xF
    mov  r1, #0
    bl   lcd_send_nibble

    ldr  r0, =T_37US            /* wait for command to execute      */
    bl   delay

    pop  {r4, pc}

/* ================================================================
 * lcd_data  —  send a data byte (character) to the LCD  (RS = 1)
 * r0 = ASCII character
 * ================================================================ */
.thumb_func
lcd_data:
    push {r4, lr}
    mov  r4, r0

    /* High nibble first */
    lsr  r0, r4, #4
    and  r0, r0, #0xF
    mov  r1, #1                 /* RS = 1: data                     */
    bl   lcd_send_nibble

    /* Then low nibble */
    and  r0, r4, #0xF
    mov  r1, #1
    bl   lcd_send_nibble

    ldr  r0, =T_37US
    bl   delay

    pop  {r4, pc}

/* ================================================================
 * lcd_send_nibble  —  put a 4-bit nibble on D4-D7 and strobe EN
 *
 * r0 = nibble  [3:0]   (upper bits ignored)
 * r1 = RS flag         (0 = command,  1 = data)
 *
 * Protocol:
 *   ① reset all LCD pins (EN and data lines low)
 *   ② set RS and data lines; EN stays low (setup time)
 *   ③ EN → HIGH  (controller latches on falling edge)
 *   ④ wait ≥450 ns
 *   ⑤ EN → LOW
 *   ⑥ wait ≥10 ns data hold
 * ================================================================ */
.thumb_func
lcd_send_nibble:
    push {r4, r5, lr}

    ldr  r4, =GPIOB_BSRR

    /* ① Drive RS, EN, D4-D7 all low via BSRR reset field */
    ldr  r5, =LCD_RST
    str  r5, [r4]

    /* ② Place nibble on D4-D7 (bits [7:4]) and set RS if needed */
    lsl  r5, r0, #4             /* nibble → PB[7:4]                 */
    and  r5, r5, #0xF0          /* mask to data bits only           */
    cmp  r1, #0
    beq  rs_stays_low
    orr  r5, r5, #RS_BIT        /* RS = 1 for data writes           */
rs_stays_low:
    str  r5, [r4]               /* data + RS stable; EN still low   */

    /* Setup hold time: ~24 iter × 35.7 ns ≈ 857 ns  (spec: ≥80 ns) */
    mov  r0, #24
    bl   delay

    /* ③ EN HIGH */
    mov  r5, #EN_BIT
    str  r5, [r4]

    /* ④ EN pulse width: ~50 iter × 35.7 ns ≈ 1.78 µs  (spec: ≥450 ns) */
    mov  r0, #50
    bl   delay

    /* ⑤ EN LOW — move EN_BIT into BSRR reset field (bits [31:16]) */
    mov  r5, #EN_BIT
    lsl  r5, r5, #16
    str  r5, [r4]

    /* ⑥ Data hold: same guard as setup */
    mov  r0, #24
    bl   delay

    pop  {r4, r5, pc}

/* ================================================================
 * delay  —  software busy-wait spin loop
 * r0 = iteration count  (≈ 3 CPU cycles per iteration @ 84 MHz)
 * ================================================================ */
.thumb_func
delay:
    subs r0, r0, #1
    bne  delay
    bx   lr

/* Literal pool — must be within ±4 KB of all ldr= instructions */
.ltorg

.end