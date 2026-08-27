.syntax unified
.cpu cortex-m4
.thumb

.equ RCC_AHB1ENR,  0x40023830
.equ GPIOA_MODER,  0x40020000
.equ GPIOA_PUPDR,  0x4002000C
.equ GPIOA_IDR,    0x40020010
.equ GPIOA_BSRR,   0x40020018
.equ GPIOB_MODER,  0x40020400
.equ GPIOB_BSRR,   0x40020418

.equ LCD_RS,       (1 <<  0)
.equ LCD_E,        (1 <<  1)
.equ LCD_D4,       (1 <<  4)
.equ LCD_D5,       (1 <<  5)
.equ LCD_D6,       (1 <<  6)
.equ LCD_D7,       (1 <<  7)
.equ LCD_RS_CLR,   (LCD_RS  << 16)
.equ LCD_E_CLR,    (LCD_E   << 16)
.equ LCD_DATA_CLR, ((LCD_D4|LCD_D5|LCD_D6|LCD_D7) << 16)
.equ LCD_ALL_CLR,  ((LCD_RS|LCD_E|LCD_D4|LCD_D5|LCD_D6|LCD_D7) << 16)

@ PA0=CLK  PA1=DT  PA4=SW  PA6=DHT
@ PA2 and PA3 are USART2 (ST-Link COM port) — do NOT use them
.equ ENC_CLK,      (1 << 0)
.equ ENC_DT,       (1 << 1)
.equ ENC_SW,       (1 << 4)   @ moved from PA2 to PA4
.equ DHT_PIN,      (1 << 6)   @ moved from PA3 to PA6
.equ DHT_CLR,      (1 << 22)  @ PA6 BSRR reset bit (6+16=22)

.equ STATE_HOME,   0
.equ STATE_MENU,   1
.equ DHT_INTERVAL, 400

@ -----------------------------------------------------------------------
.data
.align 2
g_prev_clk:  .byte 1
g_prev_sw:   .byte 1
g_selection: .byte 1
g_state:     .byte 0
g_mode:      .byte 0
g_fan:       .byte 0
g_room:      .byte 1
g_status:    .byte 0
g_temp:      .byte 25
g_hum:       .byte 50
.align 2
g_dht_timer: .word 0
g_dht_buf:   .space 5
.align 2

@ -----------------------------------------------------------------------
.section .rodata
.align 2
str_hdr:      .asciz "   ** MENU **       "
str_pfx:      .asciz " > Option "
str_main_scr: .asciz " > Main Screen      "
str_blk:      .asciz "                    "
str_temp_pfx: .asciz "Temp: "
str_temp_c:   .asciz "C  Hum: "
str_hum_pct:  .asciz "%  "
str_mode_pfx: .asciz "Mode:["
str_mode_a:   .asciz "A]   Fan:["
str_mode_m:   .asciz "M]   Fan:["
str_fan_off:  .asciz "OFF]"
str_fan_on:   .asciz "ON] "
str_room_pfx: .asciz "Room: "
str_stat_pfx: .asciz "  Stat: "
str_stat_rt:  .asciz "RT  "
str_stat_h:   .asciz "H   "
str_stat_c:   .asciz "C   "
str_home_r3:  .asciz "Push knob for menu  "

@ -----------------------------------------------------------------------
.text
.align 2
.global setup
.global loop

@ -----------------------------------------------------------------------
@ delay_us: busy-wait r0 microseconds (84 MHz)
@ -----------------------------------------------------------------------
.thumb_func
delay_us:
    push  {r4, lr}
    ldr   r4, =28
    mul   r0, r0, r4
.L_dus:
    subs  r0, r0, #1
    bhi   .L_dus
    pop   {r4, pc}

@ -----------------------------------------------------------------------
@ delay_ms: busy-wait r0 milliseconds
@ -----------------------------------------------------------------------
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

@ -----------------------------------------------------------------------
@ lcd_set_nibble
@ -----------------------------------------------------------------------
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

@ -----------------------------------------------------------------------
@ lcd_pulse_e
@ -----------------------------------------------------------------------
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

@ -----------------------------------------------------------------------
@ lcd_send_nibble
@ -----------------------------------------------------------------------
.thumb_func
lcd_send_nibble:
    push  {lr}
    bl    lcd_set_nibble
    bl    lcd_pulse_e
    pop   {pc}

@ -----------------------------------------------------------------------
@ lcd_cmd
@ -----------------------------------------------------------------------
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

@ -----------------------------------------------------------------------
@ lcd_data
@ -----------------------------------------------------------------------
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

@ -----------------------------------------------------------------------
@ lcd_print
@ -----------------------------------------------------------------------
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

@ -----------------------------------------------------------------------
@ lcd_goto: row r0 (0-3), col r1 (0-19)
@ -----------------------------------------------------------------------
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

@ -----------------------------------------------------------------------
@ lcd_init
@ -----------------------------------------------------------------------
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

@ -----------------------------------------------------------------------
@ print_decimal_2: print 1-or-2 digit decimal from r0
@ -----------------------------------------------------------------------
.thumb_func
print_decimal_2:
    push  {r4, r5, lr}
    movs  r4, r0
    movs  r5, #0
.L_pd2_tens:
    cmp   r4, #10
    blt   .L_pd2_write_tens
    subs  r4, r4, #10
    add   r5, r5, #1
    b     .L_pd2_tens
.L_pd2_write_tens:
    cmp   r5, #0
    beq   .L_pd2_units
    add   r0, r5, #'0'
    bl    lcd_data
.L_pd2_units:
    add   r0, r4, #'0'
    bl    lcd_data
    pop   {r4, r5, pc}

@ -----------------------------------------------------------------------
@ update_status: >=28->H(1), <=18->C(2), else->RT(0)
@ -----------------------------------------------------------------------
.thumb_func
update_status:
    push  {r4, lr}
    ldr   r4, =g_temp
    ldrb  r4, [r4]
    ldr   r0, =g_status
    cmp   r4, #28
    bge   .Lus_hot
    cmp   r4, #18
    ble   .Lus_cold
    movs  r1, #0
    strb  r1, [r0]
    pop   {r4, pc}
.Lus_hot:
    movs  r1, #1
    strb  r1, [r0]
    pop   {r4, pc}
.Lus_cold:
    movs  r1, #2
    strb  r1, [r0]
    pop   {r4, pc}

@ -----------------------------------------------------------------------
@ draw_home
@ -----------------------------------------------------------------------
.thumb_func
draw_home:
    push  {r4, r5, lr}

    movs  r0, #0
    movs  r1, #0
    bl    lcd_goto
    ldr   r0, =str_temp_pfx
    bl    lcd_print
    ldr   r4, =g_temp
    ldrb  r0, [r4]
    bl    print_decimal_2
    ldr   r0, =str_temp_c
    bl    lcd_print
    ldr   r4, =g_hum
    ldrb  r0, [r4]
    bl    print_decimal_2
    ldr   r0, =str_hum_pct
    bl    lcd_print

    movs  r0, #1
    movs  r1, #0
    bl    lcd_goto
    ldr   r0, =str_mode_pfx
    bl    lcd_print
    ldr   r4, =g_mode
    ldrb  r4, [r4]
    cmp   r4, #0
    bne   .Ldh_mode_m
    ldr   r0, =str_mode_a
    bl    lcd_print
    b     .Ldh_fan
.Ldh_mode_m:
    ldr   r0, =str_mode_m
    bl    lcd_print
.Ldh_fan:
    ldr   r4, =g_fan
    ldrb  r4, [r4]
    cmp   r4, #0
    bne   .Ldh_fan_on
    ldr   r0, =str_fan_off
    bl    lcd_print
    b     .Ldh_r2
.Ldh_fan_on:
    ldr   r0, =str_fan_on
    bl    lcd_print

.Ldh_r2:
    movs  r0, #2
    movs  r1, #0
    bl    lcd_goto
    ldr   r0, =str_room_pfx
    bl    lcd_print
    ldr   r4, =g_room
    ldrb  r0, [r4]
    add   r0, r0, #'0'
    bl    lcd_data
    ldr   r0, =str_stat_pfx
    bl    lcd_print
    ldr   r4, =g_status
    ldrb  r4, [r4]
    cmp   r4, #1
    beq   .Ldh_stat_h
    cmp   r4, #2
    beq   .Ldh_stat_c
    ldr   r0, =str_stat_rt
    bl    lcd_print
    b     .Ldh_r3
.Ldh_stat_h:
    ldr   r0, =str_stat_h
    bl    lcd_print
    b     .Ldh_r3
.Ldh_stat_c:
    ldr   r0, =str_stat_c
    bl    lcd_print

.Ldh_r3:
    movs  r0, #3
    movs  r1, #0
    bl    lcd_goto
    ldr   r0, =str_home_r3
    bl    lcd_print

    pop   {r4, r5, pc}

@ -----------------------------------------------------------------------
@ draw_menu
@ -----------------------------------------------------------------------
.thumb_func
draw_menu:
    push  {r4, r5, lr}

    ldr   r4, =g_selection
    ldrb  r4, [r4]

    movs  r0, #0
    movs  r1, #0
    bl    lcd_goto
    ldr   r0, =str_hdr
    bl    lcd_print

    movs  r0, #1
    movs  r1, #0
    bl    lcd_goto
    cmp   r4, #6
    beq   .Ldm_main
    ldr   r0, =str_pfx
    bl    lcd_print
    movs  r0, r4
    add   r0, r0, #'0'
    bl    lcd_data
    movs  r5, #9
.Ldm_pad:
    movs  r0, #' '
    bl    lcd_data
    subs  r5, r5, #1
    bne   .Ldm_pad
    b     .Ldm_r2
.Ldm_main:
    ldr   r0, =str_main_scr
    bl    lcd_print

.Ldm_r2:
    movs  r0, #2
    movs  r1, #0
    bl    lcd_goto
    ldr   r0, =str_blk
    bl    lcd_print

    movs  r0, #3
    movs  r1, #0
    bl    lcd_goto
    movs  r0, #' '
    bl    lcd_data
    bl    lcd_data
    movs  r0, #'['
    bl    lcd_data
    movs  r0, r4
    add   r0, r0, #'0'
    bl    lcd_data
    movs  r0, #'/'
    bl    lcd_data
    movs  r0, #'6'
    bl    lcd_data
    movs  r0, #']'
    bl    lcd_data
    movs  r0, #' '
    bl    lcd_data
    bl    lcd_data
    movs  r0, #'<'
    bl    lcd_data
    bl    lcd_data
    movs  r0, #' '
    bl    lcd_data
    movs  r0, #'r'
    bl    lcd_data
    movs  r0, #'o'
    bl    lcd_data
    movs  r0, #'t'
    bl    lcd_data
    movs  r0, #'a'
    bl    lcd_data
    movs  r0, #'t'
    bl    lcd_data
    movs  r0, #'e'
    bl    lcd_data
    movs  r0, #' '
    bl    lcd_data
    bl    lcd_data

    pop   {r4, r5, pc}

@ -----------------------------------------------------------------------
@ dht11_read: bit-bang DHT11 on PA6
@
@ PA6 MODER bits = [13:12]
@ DHT_PIN = (1<<6) for IDR reads
@ DHT_CLR = (1<<22) for BSRR reset (pin 6 + 16 = 22)
@ -----------------------------------------------------------------------
.thumb_func
dht11_read:
    push  {r4, r5, r6, r7, r8, lr}

    ldr   r6, =GPIOA_MODER
    ldr   r7, =GPIOA_BSRR
    ldr   r8, =GPIOA_IDR

    @ PA6 as output: set MODER bits[13:12] = 01
    ldr   r4, [r6]
    bic   r4, r4, #(3 << 12)
    orr   r4, r4, #(1 << 12)
    str   r4, [r6]

    @ Pull low 20 ms (start signal)
    ldr   r0, =DHT_CLR
    str   r0, [r7]
    movs  r0, #20
    bl    delay_ms

    @ Pull high 30 us then release
    ldr   r0, =DHT_PIN
    str   r0, [r7]
    movs  r0, #30
    bl    delay_us

    @ PA6 back to input: MODER bits[13:12] = 00
    ldr   r4, [r6]
    bic   r4, r4, #(3 << 12)
    str   r4, [r6]

    @ Wait for DHT to pull low
    ldr   r5, =10000
.L_wait_low:
    ldr   r4, [r8]
    tst   r4, #DHT_PIN
    beq   .L_got_low
    subs  r5, r5, #1
    bne   .L_wait_low
    b     .L_dht_fail
.L_got_low:

    @ Wait for DHT to pull high
    ldr   r5, =10000
.L_wait_high:
    ldr   r4, [r8]
    tst   r4, #DHT_PIN
    bne   .L_got_high
    subs  r5, r5, #1
    bne   .L_wait_high
    b     .L_dht_fail
.L_got_high:

    @ Wait for 80 us high response to end
    ldr   r5, =10000
.L_wait_high2:
    ldr   r4, [r8]
    tst   r4, #DHT_PIN
    beq   .L_start_bits
    subs  r5, r5, #1
    bne   .L_wait_high2
    b     .L_dht_fail

    @ Read 40 bits
.L_start_bits:
    ldr   r0, =g_dht_buf
    movs  r5, #5
    movs  r3, #0
    movs  r2, #8

.L_next_byte:
    cmp   r5, #0
    beq   .L_dht_done
.L_next_bit:
    cmp   r2, #0
    beq   .L_store_byte

    @ Wait for low preamble
    ldr   r4, =10000
.L_wait_pream:
    ldr   r1, [r8]
    tst   r1, #DHT_PIN
    beq   .L_pream_end
    subs  r4, r4, #1
    bne   .L_wait_pream
    b     .L_dht_fail
.L_pream_end:
    ldr   r4, =10000
.L_wait_pream2:
    ldr   r1, [r8]
    tst   r1, #DHT_PIN
    bne   .L_pream2_end
    subs  r4, r4, #1
    bne   .L_wait_pream2
    b     .L_dht_fail
.L_pream2_end:

    @ Count high duration (0-bit ~26us, 1-bit ~70us, threshold=400)
    movs  r4, #0
.L_count_high:
    ldr   r1, [r8]
    tst   r1, #DHT_PIN
    beq   .L_high_done
    add   r4, r4, #1
    ldr   r1, =2000
    cmp   r4, r1
    bge   .L_dht_fail
    b     .L_count_high
.L_high_done:
    lsls  r3, r3, #1
    ldr   r1, =400
    cmp   r4, r1
    blt   .L_bit_done
    orr   r3, r3, #1
.L_bit_done:
    subs  r2, r2, #1
    b     .L_next_bit

.L_store_byte:
    strb  r3, [r0], #1
    movs  r3, #0
    movs  r2, #8
    subs  r5, r5, #1
    b     .L_next_byte

.L_dht_done:
    @ Verify checksum
    ldr   r0, =g_dht_buf
    ldrb  r1, [r0, #0]
    ldrb  r2, [r0, #1]
    ldrb  r3, [r0, #2]
    ldrb  r4, [r0, #3]
    ldrb  r5, [r0, #4]
    add   r1, r1, r2
    add   r1, r1, r3
    add   r1, r1, r4
    and   r1, r1, #0xFF
    cmp   r1, r5
    bne   .L_dht_fail

    @ Update globals
    ldr   r0, =g_dht_buf
    ldrb  r1, [r0, #0]
    ldr   r2, =g_hum
    strb  r1, [r2]
    ldrb  r1, [r0, #2]
    ldr   r2, =g_temp
    strb  r1, [r2]
    bl    update_status
    b     .L_dht_exit

.L_dht_fail:
.L_dht_exit:
    @ Restore PA6 as input
    ldr   r4, [r6]
    bic   r4, r4, #(3 << 12)
    str   r4, [r6]

    pop   {r4, r5, r6, r7, r8, pc}

@ -----------------------------------------------------------------------
@ init_gpio
@
@ Only configure the pins we actually use — do NOT touch PA2/PA3
@ (those belong to USART2 / ST-Link)
@
@ PA0 CLK, PA1 DT, PA4 SW, PA6 DHT  -> input, pull-up
@   MODER clear mask : PA0[1:0]+PA1[3:2]+PA4[9:8]+PA6[13:12] = 0x330F
@   PUPDR set mask   : 01 for each pin                        = 0x1105
@
@ PB0,1,4,5,6,7 -> output
@   MODER clear 0xFF0F  set 0x5505
@ -----------------------------------------------------------------------
.thumb_func
init_gpio:
    push  {r4, r5, lr}

    @ Enable GPIOA + GPIOB clocks
    ldr   r4, =RCC_AHB1ENR
    ldr   r5, [r4]
    orr   r5, r5, #0x3
    str   r5, [r4]

    @ PA0, PA1, PA4, PA6: input mode (clear only those bits)
    ldr   r4, =GPIOA_MODER
    ldr   r5, [r4]
    ldr   r0, =0x330F
    bic   r5, r5, r0
    str   r5, [r4]

    @ PA0, PA1, PA4, PA6: pull-up
    ldr   r4, =GPIOA_PUPDR
    ldr   r5, [r4]
    ldr   r0, =0x330F         @ clear first
    bic   r5, r5, r0
    ldr   r0, =0x1105         @ set pull-up (01) for each pin
    orr   r5, r5, r0
    str   r5, [r4]

    @ PB0,1,4,5,6,7: output mode
    ldr   r4, =GPIOB_MODER
    ldr   r5, [r4]
    ldr   r0, =0xFF0F
    bic   r5, r5, r0
    ldr   r0, =0x5505
    orr   r5, r5, r0
    str   r5, [r4]

    @ Drive all LCD pins low
    ldr   r4, =GPIOB_BSRR
    ldr   r5, =LCD_ALL_CLR
    str   r5, [r4]

    pop   {r4, r5, pc}

@ -----------------------------------------------------------------------
@ setup
@ -----------------------------------------------------------------------
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

    ldr   r0, =g_prev_sw
    movs  r1, #1
    strb  r1, [r0]

    ldr   r0, =g_state
    movs  r1, #STATE_HOME
    strb  r1, [r0]

    ldr   r0, =g_dht_timer
    ldr   r1, =DHT_INTERVAL
    str   r1, [r0]

    bl    dht11_read
    bl    draw_home

    pop   {pc}

@ -----------------------------------------------------------------------
@ loop
@ -----------------------------------------------------------------------
.thumb_func
loop:
    push  {r4, r5, r6, r7, lr}

    ldr   r0, =GPIOA_IDR
    ldr   r0, [r0]

    @ r4 = CLK normalized (0 or ENC_CLK value)
    and   r4, r0, #ENC_CLK

    @ r5 = DT normalized to 0 or 1
    and   r5, r0, #ENC_DT
    lsr   r5, r5, #1

    @ r6 = SW normalized to 0 or 1 (PA4 = bit 4, shift right 4)
    and   r6, r0, #ENC_SW
    lsr   r6, r6, #4

    ldr   r7, =g_prev_clk
    ldrb  r7, [r7]

    ldr   r0, =g_state
    ldrb  r0, [r0]
    cmp   r0, #STATE_MENU
    beq   .Lloop_menu

    @ ================================================================
    @ HOME STATE
    @ ================================================================
    ldr   r0, =g_prev_sw
    ldrb  r0, [r0]
    cmp   r0, #1
    bne   .Lhome_no_sw
    cmp   r6, #0
    bne   .Lhome_no_sw

    @ Knob pushed: enter menu
    ldr   r0, =g_state
    movs  r1, #STATE_MENU
    strb  r1, [r0]
    ldr   r0, =g_selection
    movs  r1, #1
    strb  r1, [r0]
    bl    draw_menu
    b     .Lloop_update_prev

.Lhome_no_sw:
    @ DHT timed read every DHT_INTERVAL ticks
    ldr   r0, =g_dht_timer
    ldr   r1, [r0]
    add   r1, r1, #1
    str   r1, [r0]
    ldr   r2, =DHT_INTERVAL
    cmp   r1, r2
    blt   .Lhome_no_dht
    movs  r1, #0
    str   r1, [r0]
    bl    dht11_read
    bl    draw_home
    b     .Lloop_update_prev

.Lhome_no_dht:
    b     .Lloop_update_prev

    @ ================================================================
    @ MENU STATE
    @ ================================================================
.Lloop_menu:
    @ Encoder rotation: falling edge on CLK
    cmp   r7, #1
    bne   .Lmenu_no_rot
    cmp   r4, #0
    bne   .Lmenu_no_rot

    ldr   r0, =g_selection
    ldrb  r0, [r0]
    cmp   r5, #1
    beq   .Lmenu_dec
    cmp   r0, #6
    bge   .Lmenu_no_rot
    add   r0, r0, #1
    b     .Lmenu_save
.Lmenu_dec:
    cmp   r0, #1
    ble   .Lmenu_no_rot
    sub   r0, r0, #1
.Lmenu_save:
    ldr   r1, =g_selection
    strb  r0, [r1]
    bl    draw_menu

.Lmenu_no_rot:
    @ SW press in menu
    ldr   r0, =g_prev_sw
    ldrb  r0, [r0]
    cmp   r0, #1
    bne   .Lmenu_no_sw
    cmp   r6, #0
    bne   .Lmenu_no_sw

    ldr   r0, =g_selection
    ldrb  r0, [r0]
    cmp   r0, #6
    bne   .Lmenu_option_action

    @ Option 6: return to home
    ldr   r0, =g_state
    movs  r1, #STATE_HOME
    strb  r1, [r0]
    bl    dht11_read
    bl    draw_home
    b     .Lmenu_no_sw

.Lmenu_option_action:
    cmp   r0, #1
    bne   .Lopt2
    @ TODO: Option 1 action
    b     .Lmenu_no_sw
.Lopt2:
    cmp   r0, #2
    bne   .Lopt3
    @ TODO: Option 2 action
    b     .Lmenu_no_sw
.Lopt3:
    cmp   r0, #3
    bne   .Lopt4
    @ TODO: Option 3 action
    b     .Lmenu_no_sw
.Lopt4:
    cmp   r0, #4
    bne   .Lopt5
    @ TODO: Option 4 action
    b     .Lmenu_no_sw
.Lopt5:
    @ TODO: Option 5 action

.Lmenu_no_sw:

.Lloop_update_prev:
    ldr   r0, =g_prev_clk
    strb  r4, [r0]
    ldr   r0, =g_prev_sw
    strb  r6, [r0]

    movs  r0, #5
    bl    delay_ms

    pop   {r4, r5, r6, r7, pc}

@ End of file