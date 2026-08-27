@ ======================================================================
@ STM32F401RE  ·  LCD 2004 (4-bit mode) + Rotary Encoder Menu
@
@ Wiring
@   LCD (RW tied to GND):
@     RS → PB0    E  → PB1
@     D4 → PB4    D5 → PB5    D6 → PB6    D7 → PB7
@
@   Rotary Encoder (internal pull-ups enabled):
@     CLK → PA0   DT → PA1
@
@ Display layout (20 × 4):
@   Row 0:  "   ** MENU **       "  <- static header
@   Row 1:  " > Option N         "  <- current selection
@   Row 2:  "                    "  <- blank spacer
@   Row 3:  "  [N/5]  << rotate  "  <- visual indicator
@
@ System clock: 84 MHz (STM32F401RE STM32duino default)
@ Turning CW  -> increments selection (1 -> 5)
@ Turning CCW -> decrements selection (5 -> 1)
@ If direction is inverted swap the INC / DEC blocks in loop.
@ ======================================================================

.syntax unified
.cpu cortex-m4
.thumb

@ =====================================================================
@  PERIPHERAL ADDRESSES
@ =====================================================================
.equ RCC_AHB1ENR,   0x40023830

.equ GPIOA_MODER,   0x40020000
.equ GPIOA_PUPDR,   0x4002000C
.equ GPIOA_IDR,     0x40020010

.equ GPIOB_MODER,   0x40020400
.equ GPIOB_BSRR,    0x40020418

@ =====================================================================
@  LCD PIN BIT-MASKS  (GPIOB)
@  BSRR: lower 16 bits = set pins, upper 16 bits = reset pins
@ =====================================================================
.equ LCD_RS,        (1 <<  0)
.equ LCD_E,         (1 <<  1)
.equ LCD_D4,        (1 <<  4)
.equ LCD_D5,        (1 <<  5)
.equ LCD_D6,        (1 <<  6)
.equ LCD_D7,        (1 <<  7)

.equ LCD_RS_CLR,    (LCD_RS  << 16)
.equ LCD_E_CLR,     (LCD_E   << 16)
.equ LCD_DATA_CLR,  ((LCD_D4|LCD_D5|LCD_D6|LCD_D7) << 16)
.equ LCD_ALL_CLR,   ((LCD_RS|LCD_E|LCD_D4|LCD_D5|LCD_D6|LCD_D7) << 16)

@ =====================================================================
@  ENCODER PIN BIT-MASKS  (GPIOA)
@ =====================================================================
.equ ENC_CLK,       (1 << 0)
.equ ENC_DT,        (1 << 1)

@ =====================================================================
@  DATA SECTION
@ =====================================================================
.data
.align 2
g_prev_clk:   .byte 1
g_selection:  .byte 1
g_redraw:     .byte 0
.align 2

@ =====================================================================
@  STRING LITERALS
@ =====================================================================
.section .rodata
.align 2

str_hdr:  .asciz "   ** MENU **       "
str_pfx:  .asciz " > Option "
str_blk:  .asciz "                    "
str_r3a:  .asciz "  ["
str_r3b:  .asciz "/5]  << rotate  "

@ =====================================================================
@  CODE SECTION
@ =====================================================================
.text
.align 2

.global setup
.global loop

@ ====================================================================
@  delay_us  -  busy-wait r0 microseconds  (84 MHz: 28 iters/us)
@ ====================================================================
.thumb_func
delay_us:
    push  {r4, lr}
    ldr   r4, =28
    mul   r0, r0, r4
.L_dus:
    subs  r0, r0, #1
    bhi   .L_dus
    pop   {r4, pc}

@ ====================================================================
@  delay_ms  -  busy-wait r0 milliseconds
@ ====================================================================
.thumb_func
delay_ms:
    push  {r4, lr}
    movs  r4, r0
.L_dms:
    movs  r0, #1000
    bl    delay_us
    subs  r4, r4, #1
    bne   .L_dms
    pop   {r4, pc}

@ ====================================================================
@  lcd_set_nibble  -  drive D4-D7 from bits[7:4] of r0
@    bit7->D7(PB7)  bit6->D6  bit5->D5  bit4->D4(PB4)
@ ====================================================================
.thumb_func
lcd_set_nibble:
    push  {r4, r5, lr}
    movs  r4, r0
    ldr   r5, =GPIOB_BSRR

    ldr   r0, =LCD_DATA_CLR
    str   r0, [r5]

    movs  r1, #0

    tst   r4, #0x80
    beq   .Lsn_d6
    ldr   r0, =LCD_D7
    orr   r1, r1, r0
.Lsn_d6:
    tst   r4, #0x40
    beq   .Lsn_d5
    ldr   r0, =LCD_D6
    orr   r1, r1, r0
.Lsn_d5:
    tst   r4, #0x20
    beq   .Lsn_d4
    ldr   r0, =LCD_D5
    orr   r1, r1, r0
.Lsn_d4:
    tst   r4, #0x10
    beq   .Lsn_wr
    ldr   r0, =LCD_D4
    orr   r1, r1, r0
.Lsn_wr:
    str   r1, [r5]
    pop   {r4, r5, pc}

@ ====================================================================
@  lcd_pulse_e  -  pulse Enable high then low (2 us each phase)
@ ====================================================================
.thumb_func
lcd_pulse_e:
    push  {lr}
    ldr   r0, =GPIOB_BSRR
    ldr   r1, =LCD_E
    str   r1, [r0]
    movs  r0, #2
    bl    delay_us
    ldr   r0, =GPIOB_BSRR
    ldr   r1, =LCD_E_CLR
    str   r1, [r0]
    movs  r0, #2
    bl    delay_us
    pop   {pc}

@ ====================================================================
@  lcd_send_nibble  -  set D4-D7 from bits[7:4] of r0, then pulse E
@ ====================================================================
.thumb_func
lcd_send_nibble:
    push  {lr}
    bl    lcd_set_nibble
    bl    lcd_pulse_e
    pop   {pc}

@ ====================================================================
@  lcd_cmd  -  send command byte r0  (RS = 0)
@ ====================================================================
.thumb_func
lcd_cmd:
    push  {r4, lr}
    movs  r4, r0

    ldr   r0, =GPIOB_BSRR
    ldr   r1, =LCD_RS_CLR
    str   r1, [r0]

    movs  r0, r4
    and   r0, r0, #0xF0
    bl    lcd_send_nibble

    and   r0, r4, #0x0F
    lsls  r0, r0, #4
    bl    lcd_send_nibble

    movs  r0, #2
    bl    delay_ms
    pop   {r4, pc}

@ ====================================================================
@  lcd_data  -  send data byte r0  (RS = 1)
@ ====================================================================
.thumb_func
lcd_data:
    push  {r4, lr}
    movs  r4, r0

    ldr   r0, =GPIOB_BSRR
    ldr   r1, =LCD_RS
    str   r1, [r0]

    movs  r0, r4
    and   r0, r0, #0xF0
    bl    lcd_send_nibble

    and   r0, r4, #0x0F
    lsls  r0, r0, #4
    bl    lcd_send_nibble

    ldr   r0, =GPIOB_BSRR
    ldr   r1, =LCD_RS_CLR
    str   r1, [r0]

    movs  r0, #50
    bl    delay_us
    pop   {r4, pc}

@ ====================================================================
@  lcd_print  -  print null-terminated string at r0
@ ====================================================================
.thumb_func
lcd_print:
    push  {r4, lr}
    movs  r4, r0
.L_lp:
    ldrb  r0, [r4], #1
    cmp   r0, #0
    beq   .L_lp_done
    bl    lcd_data
    b     .L_lp
.L_lp_done:
    pop   {r4, pc}

@ ====================================================================
@  lcd_goto  -  move cursor to row r0 (0-3), col r1 (0-19)
@    DDRAM offsets: row0=0x00  row1=0x40  row2=0x14  row3=0x54
@ ====================================================================
.thumb_func
lcd_goto:
    push  {r4, r5, lr}
    movs  r4, r0
    movs  r5, r1

    movs  r0, #0x00
    cmp   r4, #1
    bne   .Lg_r2
    movs  r0, #0x40
    b     .Lg_col
.Lg_r2:
    cmp   r4, #2
    bne   .Lg_r3
    movs  r0, #0x14
    b     .Lg_col
.Lg_r3:
    cmp   r4, #3
    bne   .Lg_col
    movs  r0, #0x54
.Lg_col:
    add   r0, r0, r5
    orr   r0, r0, #0x80
    bl    lcd_cmd
    pop   {r4, r5, pc}

@ ====================================================================
@  lcd_init  -  HD44780 4-bit initialisation sequence
@ ====================================================================
.thumb_func
lcd_init:
    push  {lr}

    ldr   r0, =GPIOB_BSRR
    ldr   r1, =LCD_ALL_CLR
    str   r1, [r0]

    movs  r0, #50
    bl    delay_ms

    movs  r0, #0x30
    bl    lcd_send_nibble
    movs  r0, #5
    bl    delay_ms

    movs  r0, #0x30
    bl    lcd_send_nibble
    movs  r0, #1
    bl    delay_ms

    movs  r0, #0x30
    bl    lcd_send_nibble
    movs  r0, #1
    bl    delay_ms

    movs  r0, #0x20
    bl    lcd_send_nibble
    movs  r0, #1
    bl    delay_ms

    movs  r0, #0x28
    bl    lcd_cmd

    movs  r0, #0x08
    bl    lcd_cmd

    movs  r0, #0x01
    bl    lcd_cmd
    movs  r0, #3
    bl    delay_ms

    movs  r0, #0x06
    bl    lcd_cmd

    movs  r0, #0x0C
    bl    lcd_cmd

    pop   {pc}

@ ====================================================================
@  draw_menu  -  refresh all four rows from g_selection
@
@   Row 0: "   ** MENU **       "   (20 chars, static)
@   Row 1: " > Option N         "   (10 + 1 digit + 9 spaces = 20)
@   Row 2: "                    "   (20 spaces, static)
@   Row 3: "  [N/5]  << rotate  "   (3 + 1 digit + 16 = 20)
@ ====================================================================
.thumb_func
draw_menu:
    push  {r4, lr}

    ldr   r4, =g_selection
    ldrb  r4, [r4]

    @ Row 0
    movs  r0, #0
    movs  r1, #0
    bl    lcd_goto
    ldr   r0, =str_hdr
    bl    lcd_print

    @ Row 1
    movs  r0, #1
    movs  r1, #0
    bl    lcd_goto
    ldr   r0, =str_pfx
    bl    lcd_print
    movs  r0, r4
    add   r0, r0, #'0'
    bl    lcd_data
    movs  r0, #' '
    bl    lcd_data
    bl    lcd_data
    bl    lcd_data
    bl    lcd_data
    bl    lcd_data
    bl    lcd_data
    bl    lcd_data
    bl    lcd_data
    bl    lcd_data

    @ Row 2
    movs  r0, #2
    movs  r1, #0
    bl    lcd_goto
    ldr   r0, =str_blk
    bl    lcd_print

    @ Row 3
    movs  r0, #3
    movs  r1, #0
    bl    lcd_goto
    ldr   r0, =str_r3a
    bl    lcd_print
    movs  r0, r4
    add   r0, r0, #'0'
    bl    lcd_data
    ldr   r0, =str_r3b
    bl    lcd_print

    pop   {r4, pc}

@ ====================================================================
@  init_gpio  -  enable clocks and configure pins
@
@  GPIOA  PA0, PA1  -> input with pull-up   (encoder)
@  GPIOB  PB0,1,4,5,6,7 -> push-pull output (LCD)
@
@  GPIOB MODER mask calculations:
@    PB0[1:0] PB1[3:2] PB4[9:8] PB5[11:10] PB6[13:12] PB7[15:14]
@    clear = 0xFF0F    set (mode=01) = 0x5505
@ ====================================================================
.thumb_func
init_gpio:
    push  {r4, r5, lr}

    ldr   r4, =RCC_AHB1ENR
    ldr   r5, [r4]
    orr   r5, r5, #0x3
    str   r5, [r4]

    ldr   r4, =GPIOA_MODER
    ldr   r5, [r4]
    bic   r5, r5, #0x0F
    str   r5, [r4]

    ldr   r4, =GPIOA_PUPDR
    ldr   r5, [r4]
    bic   r5, r5, #0x0F
    orr   r5, r5, #0x05
    str   r5, [r4]

    ldr   r4, =GPIOB_MODER
    ldr   r5, [r4]
    ldr   r0, =0xFF0F
    bic   r5, r5, r0
    ldr   r0, =0x5505
    orr   r5, r5, r0
    str   r5, [r4]

    ldr   r4, =GPIOB_BSRR
    ldr   r5, =LCD_ALL_CLR
    str   r5, [r4]

    pop   {r4, r5, pc}

@ ====================================================================
@  setup  -  called once by Arduino core main.cpp
@ ====================================================================
.thumb_func
setup:
    push  {lr}

    bl    init_gpio
    bl    lcd_init

    ldr   r0, =g_selection
    movs  r1, #1
    strb  r1, [r0]

    ldr   r0, =g_prev_clk
    movs  r1, #1
    strb  r1, [r0]

    ldr   r0, =g_redraw
    movs  r1, #0
    strb  r1, [r0]

    bl    draw_menu

    pop   {pc}

@ ====================================================================
@  loop  -  called repeatedly by Arduino core main.cpp
@
@  Falling edge on CLK:
@    DT = 1  ->  CCW  ->  decrement selection
@    DT = 0  ->  CW   ->  increment selection
@ ====================================================================
.thumb_func
loop:
    push  {r4, r5, r6, r7, lr}

    ldr   r0, =GPIOA_IDR
    ldr   r0, [r0]

    and   r4, r0, #ENC_CLK
    and   r5, r0, #ENC_DT
    lsr   r5, r5, #1

    ldr   r6, =g_prev_clk
    ldrb  r6, [r6]

    cmp   r6, #1
    bne   .Lno_edge
    cmp   r4, #0
    bne   .Lno_edge

    ldr   r7, =g_selection
    ldrb  r7, [r7]

    cmp   r5, #1
    beq   .Ldec

    @ CW: increment, clamp at 5
    cmp   r7, #5
    bge   .Lno_edge
    add   r7, r7, #1
    b     .Lsave

.Ldec:
    @ CCW: decrement, clamp at 1
    cmp   r7, #1
    ble   .Lno_edge
    sub   r7, r7, #1

.Lsave:
    ldr   r0, =g_selection
    strb  r7, [r0]

    ldr   r0, =g_redraw
    movs  r1, #1
    strb  r1, [r0]

.Lno_edge:
    ldr   r0, =g_prev_clk
    strb  r4, [r0]

    ldr   r0, =g_redraw
    ldrb  r0, [r0]
    cmp   r0, #0
    beq   .Lend

    ldr   r0, =g_redraw
    movs  r1, #0
    strb  r1, [r0]

    bl    draw_menu

.Lend:
    movs  r0, #5
    bl    delay_ms

    pop   {r4, r5, r6, r7, pc}

@ End of file