.syntax unified
.cpu cortex-m4
.thumb

@ ---- Peripheral registers ----
.equ RCC_AHB1ENR,  0x40023830
.equ GPIOA_MODER,  0x40020000
.equ GPIOA_PUPDR,  0x4002000C
.equ GPIOA_IDR,    0x40020010
.equ GPIOA_BSRR,   0x40020018
.equ GPIOB_MODER,  0x40020400
.equ GPIOB_BSRR,   0x40020418

@ ---- LCD pins (GPIOB) ----
.equ LCD_RS,       (1 << 0)
.equ LCD_E,        (1 << 1)
.equ LCD_D4,       (1 << 4)
.equ LCD_D5,       (1 << 5)
.equ LCD_D6,       (1 << 6)
.equ LCD_D7,       (1 << 7)
.equ LCD_RS_CLR,   (LCD_RS << 16)
.equ LCD_E_CLR,    (LCD_E  << 16)
.equ LCD_DATA_CLR, ((LCD_D4|LCD_D5|LCD_D6|LCD_D7) << 16)
.equ LCD_ALL_CLR,  ((LCD_RS|LCD_E|LCD_D4|LCD_D5|LCD_D6|LCD_D7) << 16)

@ ---- Encoder & DHT (GPIOA) ----
@ PA2/PA3 are USART2 (ST-Link) — do NOT use them
.equ ENC_CLK,      (1 << 0)   @ PA0
.equ ENC_DT,       (1 << 1)   @ PA1
.equ ENC_SW,       (1 << 4)   @ PA4
.equ DHT_PIN,      (1 << 6)   @ PA6
.equ DHT_CLR,      (1 << 22)  @ PA6 BSRR reset (6+16)

@ ---- Menu states ----
.equ STATE_HOME,      0
.equ STATE_MENU,      1   @ Mode / Threshold / Manual / Main Screen
.equ STATE_MODE,      2   @ Manual / Auto / Back
.equ STATE_THRESHOLD, 3   @ (Coming soon) / Back
.equ STATE_MANUAL,    4   @ Fan 1 / Fan 2 / Back
.equ STATE_FAN1,      5   @ Off / On / Back
.equ STATE_FAN2,      6   @ Off / On / Back

.equ DHT_INTERVAL, 400

@ ================================================================
@ DATA
@ ================================================================
.data
.align 2
g_prev_clk:  .byte 1
g_prev_sw:   .byte 1
g_selection: .byte 1
g_state:     .byte 0
g_mode:      .byte 0      @ 0=Auto  1=Manual
g_fan:       .byte 0      @ Fan 1: 0=OFF 1=ON
g_fan2:      .byte 0      @ Fan 2: 0=OFF 1=ON
g_room:      .byte 1
g_status:    .byte 0      @ 0=RT 1=H 2=C
g_temp:      .byte 25
g_hum:       .byte 50
.align 2
g_dht_timer: .word 0
g_dht_buf:   .space 5
.align 2

@ ================================================================
@ STRINGS
@ ================================================================
.section .rodata
.align 2

@ ---- Utility ----
str_blk:       .asciz "                    "

@ ---- Home screen pieces ----
@ Row 0: "Temp: XXC  Hum: XX% "
str_temp_pfx:  .asciz "Temp: "
str_temp_c:    .asciz "C  Hum: "
str_hum_pct:   .asciz "% "
@ Row 1: "Mode:[A]  Fan1:[OFF]"
str_mode_pfx:  .asciz "Mode:["
str_fan1_mid:  .asciz "]  Fan1:["
@ Row 2: "F2:[OFF] Rm:X St:RT "
str_fan2_pfx:  .asciz "F2:["
str_fan_off:   .asciz "OFF]"
str_fan_on:    .asciz "ON] "
str_rm_pfx:    .asciz " Rm:"
str_st_pfx:    .asciz " St:"
str_st_rt:     .asciz "RT "
str_st_h:      .asciz "H  "
str_st_c:      .asciz "C  "
@ Row 3
str_home_r3:   .asciz "Push knob for menu  "

@ ---- Menu headers (20 chars each) ----
str_hdr_menu:  .asciz "   ** MENU **       "
str_hdr_mode:  .asciz "      Mode          "
str_hdr_thr:   .asciz "   Threshold        "
str_hdr_man:   .asciz "     Manual         "
str_hdr_fan1:  .asciz "     Fan 1          "
str_hdr_fan2:  .asciz "     Fan 2          "

@ ---- Menu items (18 chars each, printed after "> ") ----
str_i_mode:    .asciz "Mode              "
str_i_thr:     .asciz "Threshold         "
str_i_manual:  .asciz "Manual            "
str_i_main:    .asciz "Main Screen       "
str_i_auto:    .asciz "Auto              "
str_i_back:    .asciz "Back              "
str_i_fan1:    .asciz "Fan 1             "
str_i_fan2:    .asciz "Fan 2             "
str_i_coming:  .asciz "(Coming soon)     "
str_i_off:     .asciz "Off               "
str_i_on:      .asciz "On                "

@ ================================================================
@ CODE
@ ================================================================
.text
.align 2
.global setup
.global loop

@ ----------------------------------------------------------------
@ delay_us: busy-wait r0 µs (84 MHz)
@ ----------------------------------------------------------------
.thumb_func
delay_us:
    push {r4, lr}
    ldr  r4, =28
    mul  r0, r0, r4
.Ldus:
    subs r0, r0, #1
    bhi  .Ldus
    pop  {r4, pc}

@ ----------------------------------------------------------------
@ delay_ms: busy-wait r0 ms
@ ----------------------------------------------------------------
.thumb_func
delay_ms:
    push {r4, lr}
    movs r4, r0
.Ldms:
    movs r0, #1000
    bl   delay_us
    subs r4, r4, #1
    bne  .Ldms
    pop  {r4, pc}

@ ----------------------------------------------------------------
@ lcd_set_nibble: drive D4-D7 from bits[7:4] of r0
@ ----------------------------------------------------------------
.thumb_func
lcd_set_nibble:
    push {r4, r5, lr}
    movs r4, r0
    ldr  r5, =GPIOB_BSRR
    ldr  r0, =LCD_DATA_CLR
    str  r0, [r5]
    movs r1, #0
    tst  r4, #0x80
    beq  .Lsn_d6
    ldr  r0, =LCD_D7; orr r1, r1, r0
.Lsn_d6:
    tst  r4, #0x40
    beq  .Lsn_d5
    ldr  r0, =LCD_D6; orr r1, r1, r0
.Lsn_d5:
    tst  r4, #0x20
    beq  .Lsn_d4
    ldr  r0, =LCD_D5; orr r1, r1, r0
.Lsn_d4:
    tst  r4, #0x10
    beq  .Lsn_wr
    ldr  r0, =LCD_D4; orr r1, r1, r0
.Lsn_wr:
    str  r1, [r5]
    pop  {r4, r5, pc}

@ ----------------------------------------------------------------
@ lcd_pulse_e
@ ----------------------------------------------------------------
.thumb_func
lcd_pulse_e:
    push {lr}
    ldr  r0, =GPIOB_BSRR
    ldr  r1, =LCD_E;     str r1, [r0]
    movs r0, #2;         bl  delay_us
    ldr  r0, =GPIOB_BSRR
    ldr  r1, =LCD_E_CLR; str r1, [r0]
    movs r0, #2;         bl  delay_us
    pop  {pc}

@ ----------------------------------------------------------------
@ lcd_send_nibble
@ ----------------------------------------------------------------
.thumb_func
lcd_send_nibble:
    push {lr}
    bl   lcd_set_nibble
    bl   lcd_pulse_e
    pop  {pc}

@ ----------------------------------------------------------------
@ lcd_cmd: send command byte r0 (RS=0)
@ ----------------------------------------------------------------
.thumb_func
lcd_cmd:
    push {r4, lr}
    movs r4, r0
    ldr  r0, =GPIOB_BSRR
    ldr  r1, =LCD_RS_CLR; str r1, [r0]
    movs r0, r4; and r0, r0, #0xF0; bl lcd_send_nibble
    and  r0, r4, #0x0F; lsls r0, r0, #4; bl lcd_send_nibble
    movs r0, #2; bl delay_ms
    pop  {r4, pc}

@ ----------------------------------------------------------------
@ lcd_data: send data byte r0 (RS=1)
@ ----------------------------------------------------------------
.thumb_func
lcd_data:
    push {r4, lr}
    movs r4, r0
    ldr  r0, =GPIOB_BSRR
    ldr  r1, =LCD_RS; str r1, [r0]
    movs r0, r4; and r0, r0, #0xF0; bl lcd_send_nibble
    and  r0, r4, #0x0F; lsls r0, r0, #4; bl lcd_send_nibble
    ldr  r0, =GPIOB_BSRR
    ldr  r1, =LCD_RS_CLR; str r1, [r0]
    movs r0, #50; bl delay_us
    pop  {r4, pc}

@ ----------------------------------------------------------------
@ lcd_print: null-terminated string at r0
@ ----------------------------------------------------------------
.thumb_func
lcd_print:
    push {r4, lr}
    movs r4, r0
.Llp:
    ldrb r0, [r4], #1
    cmp  r0, #0; beq .Llp_done
    bl   lcd_data; b .Llp
.Llp_done:
    pop  {r4, pc}

@ ----------------------------------------------------------------
@ lcd_goto: row r0 (0-3), col r1 (0-19)
@ ----------------------------------------------------------------
.thumb_func
lcd_goto:
    push {r4, r5, lr}
    movs r4, r0; movs r5, r1
    movs r0, #0x00
    cmp  r4, #1; bne .Lgg2; movs r0, #0x40; b .Lggc
.Lgg2:
    cmp  r4, #2; bne .Lgg3; movs r0, #0x14; b .Lggc
.Lgg3:
    cmp  r4, #3; bne .Lggc; movs r0, #0x54
.Lggc:
    add  r0, r0, r5; orr r0, r0, #0x80; bl lcd_cmd
    pop  {r4, r5, pc}

@ ----------------------------------------------------------------
@ lcd_init: HD44780 4-bit init
@ ----------------------------------------------------------------
.thumb_func
lcd_init:
    push {lr}
    ldr  r0, =GPIOB_BSRR; ldr r1, =LCD_ALL_CLR; str r1, [r0]
    movs r0, #50; bl delay_ms
    movs r0, #0x30; bl lcd_send_nibble; movs r0, #5; bl delay_ms
    movs r0, #0x30; bl lcd_send_nibble; movs r0, #1; bl delay_ms
    movs r0, #0x30; bl lcd_send_nibble; movs r0, #1; bl delay_ms
    movs r0, #0x20; bl lcd_send_nibble; movs r0, #1; bl delay_ms
    movs r0, #0x28; bl lcd_cmd
    movs r0, #0x08; bl lcd_cmd
    movs r0, #0x01; bl lcd_cmd; movs r0, #3; bl delay_ms
    movs r0, #0x06; bl lcd_cmd
    movs r0, #0x0C; bl lcd_cmd
    pop  {pc}

@ ----------------------------------------------------------------
@ print_decimal_2: 1-or-2 digit decimal from r0
@ ----------------------------------------------------------------
.thumb_func
print_decimal_2:
    push {r4, r5, lr}
    movs r4, r0; movs r5, #0
.Lpd_t:
    cmp  r4, #10; blt .Lpd_wt
    subs r4, r4, #10; add r5, r5, #1; b .Lpd_t
.Lpd_wt:
    cmp  r5, #0; beq .Lpd_u
    add  r0, r5, #'0'; bl lcd_data
.Lpd_u:
    add  r0, r4, #'0'; bl lcd_data
    pop  {r4, r5, pc}

@ ----------------------------------------------------------------
@ update_status: >=28->H, <=18->C, else->RT
@ ----------------------------------------------------------------
.thumb_func
update_status:
    push {r4, lr}
    ldr  r4, =g_temp; ldrb r4, [r4]
    ldr  r0, =g_status
    cmp  r4, #28; bge .Lus_h
    cmp  r4, #18; ble .Lus_c
    movs r1, #0; strb r1, [r0]; pop {r4, pc}
.Lus_h:
    movs r1, #1; strb r1, [r0]; pop {r4, pc}
.Lus_c:
    movs r1, #2; strb r1, [r0]; pop {r4, pc}

@ ----------------------------------------------------------------
@ draw_home
@  Row 0: "Temp: XXC  Hum: XX% "
@  Row 1: "Mode:[A]  Fan1:[OFF]"
@  Row 2: "F2:[OFF] Rm:X St:RT "
@  Row 3: "Push knob for menu  "
@ ----------------------------------------------------------------
.thumb_func
draw_home:
    push {r4, lr}

    @ Row 0
    movs r0, #0; movs r1, #0; bl lcd_goto
    ldr  r0, =str_temp_pfx; bl lcd_print
    ldr  r4, =g_temp; ldrb r0, [r4]; bl print_decimal_2
    ldr  r0, =str_temp_c; bl lcd_print
    ldr  r4, =g_hum; ldrb r0, [r4]; bl print_decimal_2
    ldr  r0, =str_hum_pct; bl lcd_print

    @ Row 1
    movs r0, #1; movs r1, #0; bl lcd_goto
    ldr  r0, =str_mode_pfx; bl lcd_print
    ldr  r4, =g_mode; ldrb r4, [r4]
    cmp  r4, #0; bne .Ldh_mm
    movs r0, #'A'; bl lcd_data; b .Ldh_f1
.Ldh_mm:
    movs r0, #'M'; bl lcd_data
.Ldh_f1:
    ldr  r0, =str_fan1_mid; bl lcd_print
    ldr  r4, =g_fan; ldrb r4, [r4]
    cmp  r4, #0; bne .Ldh_f1on
    ldr  r0, =str_fan_off; bl lcd_print; b .Ldh_r2
.Ldh_f1on:
    ldr  r0, =str_fan_on; bl lcd_print

    @ Row 2
.Ldh_r2:
    movs r0, #2; movs r1, #0; bl lcd_goto
    ldr  r0, =str_fan2_pfx; bl lcd_print
    ldr  r4, =g_fan2; ldrb r4, [r4]
    cmp  r4, #0; bne .Ldh_f2on
    ldr  r0, =str_fan_off; bl lcd_print; b .Ldh_rm
.Ldh_f2on:
    ldr  r0, =str_fan_on; bl lcd_print
.Ldh_rm:
    ldr  r0, =str_rm_pfx; bl lcd_print
    ldr  r4, =g_room; ldrb r0, [r4]
    add  r0, r0, #'0'; bl lcd_data
    ldr  r0, =str_st_pfx; bl lcd_print
    ldr  r4, =g_status; ldrb r4, [r4]
    cmp  r4, #1; beq .Ldh_sh
    cmp  r4, #2; beq .Ldh_sc
    ldr  r0, =str_st_rt; bl lcd_print; b .Ldh_r3
.Ldh_sh:
    ldr  r0, =str_st_h; bl lcd_print; b .Ldh_r3
.Ldh_sc:
    ldr  r0, =str_st_c; bl lcd_print

    @ Row 3
.Ldh_r3:
    movs r0, #3; movs r1, #0; bl lcd_goto
    ldr  r0, =str_home_r3; bl lcd_print

    pop  {r4, pc}

@ ----------------------------------------------------------------
@ print_item_row: go to row 1 col 0, print "> " then string r0
@ ----------------------------------------------------------------
.thumb_func
print_item_row:
    push {r4, lr}
    movs r4, r0
    movs r0, #1; movs r1, #0; bl lcd_goto
    movs r0, #'>'; bl lcd_data
    movs r0, #' '; bl lcd_data
    movs r0, r4;   bl lcd_print
    pop  {r4, pc}

@ ----------------------------------------------------------------
@ print_row3: "  [sel/max] << rotate  " on row 3
@   r0 = current selection, r1 = max items
@ ----------------------------------------------------------------
.thumb_func
print_row3:
    push {r4, r5, lr}
    movs r4, r0; movs r5, r1
    movs r0, #3; movs r1, #0; bl lcd_goto
    movs r0, #' '; bl lcd_data; bl lcd_data
    movs r0, #'['; bl lcd_data
    movs r0, r4; add r0, r0, #'0'; bl lcd_data
    movs r0, #'/'; bl lcd_data
    movs r0, r5; add r0, r0, #'0'; bl lcd_data
    movs r0, #']'; bl lcd_data
    movs r0, #' '; bl lcd_data; bl lcd_data
    movs r0, #'<'; bl lcd_data; bl lcd_data
    movs r0, #' '; bl lcd_data
    movs r0, #'r'; bl lcd_data
    movs r0, #'o'; bl lcd_data
    movs r0, #'t'; bl lcd_data
    movs r0, #'a'; bl lcd_data
    movs r0, #'t'; bl lcd_data
    movs r0, #'e'; bl lcd_data
    movs r0, #' '; bl lcd_data; bl lcd_data
    pop  {r4, r5, pc}

@ ----------------------------------------------------------------
@ get_max_items: r0=state -> r0=number of items in that state
@ ----------------------------------------------------------------
.thumb_func
get_max_items:
    push {lr}
    cmp  r0, #STATE_MENU;      bne .Lgmi1
    movs r0, #4; pop {pc}
.Lgmi1:
    cmp  r0, #STATE_MODE;      bne .Lgmi2
    movs r0, #3; pop {pc}
.Lgmi2:
    cmp  r0, #STATE_THRESHOLD; bne .Lgmi3
    movs r0, #2; pop {pc}
.Lgmi3:
    movs r0, #3  @ STATE_MANUAL / STATE_FAN1 / STATE_FAN2
    pop  {pc}

@ ----------------------------------------------------------------
@ draw_current_menu: tail-call dispatch based on g_state
@   No stack frame — LR passes through to each draw function
@ ----------------------------------------------------------------
.thumb_func
draw_current_menu:
    ldr  r0, =g_state; ldrb r0, [r0]
    cmp  r0, #STATE_MENU;      beq draw_menu_top
    cmp  r0, #STATE_MODE;      beq draw_menu_mode
    cmp  r0, #STATE_THRESHOLD; beq draw_menu_thresh
    cmp  r0, #STATE_MANUAL;    beq draw_menu_manual
    cmp  r0, #STATE_FAN1;      beq draw_menu_fan1
    cmp  r0, #STATE_FAN2;      beq draw_menu_fan2
    bx   lr

@ ----------------------------------------------------------------
@ draw_menu_top: Mode / Threshold / Manual / Main Screen
@ ----------------------------------------------------------------
.thumb_func
draw_menu_top:
    push {r4, lr}
    movs r0, #0; movs r1, #0; bl lcd_goto
    ldr  r0, =str_hdr_menu; bl lcd_print
    ldr  r4, =g_selection; ldrb r4, [r4]
    cmp  r4, #1; bne .Ldmt1
    ldr  r0, =str_i_mode; bl print_item_row; b .Ldmt_bot
.Ldmt1:
    cmp  r4, #2; bne .Ldmt2
    ldr  r0, =str_i_thr; bl print_item_row; b .Ldmt_bot
.Ldmt2:
    cmp  r4, #3; bne .Ldmt3
    ldr  r0, =str_i_manual; bl print_item_row; b .Ldmt_bot
.Ldmt3:
    ldr  r0, =str_i_main; bl print_item_row
.Ldmt_bot:
    movs r0, #2; movs r1, #0; bl lcd_goto
    ldr  r0, =str_blk; bl lcd_print
    ldr  r4, =g_selection; ldrb r0, [r4]
    movs r1, #4; bl print_row3
    pop  {r4, pc}

@ ----------------------------------------------------------------
@ draw_menu_mode: Manual / Auto / Back
@ ----------------------------------------------------------------
.thumb_func
draw_menu_mode:
    push {r4, lr}
    movs r0, #0; movs r1, #0; bl lcd_goto
    ldr  r0, =str_hdr_mode; bl lcd_print
    ldr  r4, =g_selection; ldrb r4, [r4]
    cmp  r4, #1; bne .Ldmd1
    ldr  r0, =str_i_manual; bl print_item_row; b .Ldmd_bot
.Ldmd1:
    cmp  r4, #2; bne .Ldmd2
    ldr  r0, =str_i_auto; bl print_item_row; b .Ldmd_bot
.Ldmd2:
    ldr  r0, =str_i_back; bl print_item_row
.Ldmd_bot:
    movs r0, #2; movs r1, #0; bl lcd_goto
    ldr  r0, =str_blk; bl lcd_print
    ldr  r4, =g_selection; ldrb r0, [r4]
    movs r1, #3; bl print_row3
    pop  {r4, pc}

@ ----------------------------------------------------------------
@ draw_menu_thresh: (Coming soon) / Back
@ ----------------------------------------------------------------
.thumb_func
draw_menu_thresh:
    push {r4, lr}
    movs r0, #0; movs r1, #0; bl lcd_goto
    ldr  r0, =str_hdr_thr; bl lcd_print
    ldr  r4, =g_selection; ldrb r4, [r4]
    cmp  r4, #1; bne .Ldmth1
    ldr  r0, =str_i_coming; bl print_item_row; b .Ldmth_bot
.Ldmth1:
    ldr  r0, =str_i_back; bl print_item_row
.Ldmth_bot:
    movs r0, #2; movs r1, #0; bl lcd_goto
    ldr  r0, =str_blk; bl lcd_print
    ldr  r4, =g_selection; ldrb r0, [r4]
    movs r1, #2; bl print_row3
    pop  {r4, pc}

@ ----------------------------------------------------------------
@ draw_menu_manual: Fan 1 / Fan 2 / Back
@ ----------------------------------------------------------------
.thumb_func
draw_menu_manual:
    push {r4, lr}
    movs r0, #0; movs r1, #0; bl lcd_goto
    ldr  r0, =str_hdr_man; bl lcd_print
    ldr  r4, =g_selection; ldrb r4, [r4]
    cmp  r4, #1; bne .Ldmm1
    ldr  r0, =str_i_fan1; bl print_item_row; b .Ldmm_bot
.Ldmm1:
    cmp  r4, #2; bne .Ldmm2
    ldr  r0, =str_i_fan2; bl print_item_row; b .Ldmm_bot
.Ldmm2:
    ldr  r0, =str_i_back; bl print_item_row
.Ldmm_bot:
    movs r0, #2; movs r1, #0; bl lcd_goto
    ldr  r0, =str_blk; bl lcd_print
    ldr  r4, =g_selection; ldrb r0, [r4]
    movs r1, #3; bl print_row3
    pop  {r4, pc}

@ ----------------------------------------------------------------
@ draw_menu_fan1: Off / On / Back  (Fan 1)
@ ----------------------------------------------------------------
.thumb_func
draw_menu_fan1:
    push {r4, lr}
    movs r0, #0; movs r1, #0; bl lcd_goto
    ldr  r0, =str_hdr_fan1; bl lcd_print
    ldr  r4, =g_selection; ldrb r4, [r4]
    cmp  r4, #1; bne .Ldmf1a
    ldr  r0, =str_i_off; bl print_item_row; b .Ldmf1_bot
.Ldmf1a:
    cmp  r4, #2; bne .Ldmf1b
    ldr  r0, =str_i_on; bl print_item_row; b .Ldmf1_bot
.Ldmf1b:
    ldr  r0, =str_i_back; bl print_item_row
.Ldmf1_bot:
    movs r0, #2; movs r1, #0; bl lcd_goto
    ldr  r0, =str_blk; bl lcd_print
    ldr  r4, =g_selection; ldrb r0, [r4]
    movs r1, #3; bl print_row3
    pop  {r4, pc}

@ ----------------------------------------------------------------
@ draw_menu_fan2: Off / On / Back  (Fan 2)
@ ----------------------------------------------------------------
.thumb_func
draw_menu_fan2:
    push {r4, lr}
    movs r0, #0; movs r1, #0; bl lcd_goto
    ldr  r0, =str_hdr_fan2; bl lcd_print
    ldr  r4, =g_selection; ldrb r4, [r4]
    cmp  r4, #1; bne .Ldmf2a
    ldr  r0, =str_i_off; bl print_item_row; b .Ldmf2_bot
.Ldmf2a:
    cmp  r4, #2; bne .Ldmf2b
    ldr  r0, =str_i_on; bl print_item_row; b .Ldmf2_bot
.Ldmf2b:
    ldr  r0, =str_i_back; bl print_item_row
.Ldmf2_bot:
    movs r0, #2; movs r1, #0; bl lcd_goto
    ldr  r0, =str_blk; bl lcd_print
    ldr  r4, =g_selection; ldrb r0, [r4]
    movs r1, #3; bl print_row3
    pop  {r4, pc}

@ ----------------------------------------------------------------
@ handle_select: read g_state + g_selection, apply action
@ ----------------------------------------------------------------
.thumb_func
handle_select:
    push {r4, r5, lr}
    ldr  r4, =g_state;     ldrb r4, [r4]
    ldr  r5, =g_selection; ldrb r5, [r5]

    @ ---- STATE_MENU ----
    cmp  r4, #STATE_MENU; bne .Lhs_mode

    cmp  r5, #4; bne .Lhsm1            @ Main Screen
    ldr  r0, =g_state; movs r1, #STATE_HOME; strb r1, [r0]
    bl   dht11_read; bl draw_home; b .Lhs_done
.Lhsm1:
    cmp  r5, #1; bne .Lhsm2            @ Mode
    ldr  r0, =g_state; movs r1, #STATE_MODE; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #1; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done
.Lhsm2:
    cmp  r5, #2; bne .Lhsm3            @ Threshold
    ldr  r0, =g_state; movs r1, #STATE_THRESHOLD; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #1; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done
.Lhsm3:
    @ sel=3: Manual
    ldr  r0, =g_state; movs r1, #STATE_MANUAL; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #1; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done

    @ ---- STATE_MODE ----
.Lhs_mode:
    cmp  r4, #STATE_MODE; bne .Lhs_thresh

    cmp  r5, #3; bne .Lhsmd1           @ Back
    ldr  r0, =g_state; movs r1, #STATE_MENU; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #1; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done
.Lhsmd1:
    cmp  r5, #1; bne .Lhsmd2           @ Manual mode
    ldr  r0, =g_mode; movs r1, #1; strb r1, [r0]
    ldr  r0, =g_state; movs r1, #STATE_MENU; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #1; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done
.Lhsmd2:
    @ sel=2: Auto mode
    ldr  r0, =g_mode; movs r1, #0; strb r1, [r0]
    ldr  r0, =g_state; movs r1, #STATE_MENU; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #1; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done

    @ ---- STATE_THRESHOLD ----
.Lhs_thresh:
    cmp  r4, #STATE_THRESHOLD; bne .Lhs_manual

    cmp  r5, #1; beq .Lhs_done         @ Coming soon: no action
    @ sel=2: Back
    ldr  r0, =g_state; movs r1, #STATE_MENU; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #2; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done

    @ ---- STATE_MANUAL ----
.Lhs_manual:
    cmp  r4, #STATE_MANUAL; bne .Lhs_fan1

    cmp  r5, #3; bne .Lhsmn1           @ Back
    ldr  r0, =g_state; movs r1, #STATE_MENU; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #3; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done
.Lhsmn1:
    cmp  r5, #1; bne .Lhsmn2           @ Fan 1
    ldr  r0, =g_state; movs r1, #STATE_FAN1; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #1; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done
.Lhsmn2:
    @ sel=2: Fan 2
    ldr  r0, =g_state; movs r1, #STATE_FAN2; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #1; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done

    @ ---- STATE_FAN1 ----
.Lhs_fan1:
    cmp  r4, #STATE_FAN1; bne .Lhs_fan2

    cmp  r5, #3; bne .Lhsf1a           @ Back
    ldr  r0, =g_state; movs r1, #STATE_MANUAL; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #1; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done
.Lhsf1a:
    cmp  r5, #1; bne .Lhsf1b           @ Off
    ldr  r0, =g_fan; movs r1, #0; strb r1, [r0]
    ldr  r0, =g_state; movs r1, #STATE_MANUAL; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #1; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done
.Lhsf1b:
    @ sel=2: On
    ldr  r0, =g_fan; movs r1, #1; strb r1, [r0]
    ldr  r0, =g_state; movs r1, #STATE_MANUAL; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #1; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done

    @ ---- STATE_FAN2 ----
.Lhs_fan2:
    cmp  r5, #3; bne .Lhsf2a           @ Back
    ldr  r0, =g_state; movs r1, #STATE_MANUAL; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #2; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done
.Lhsf2a:
    cmp  r5, #1; bne .Lhsf2b           @ Off
    ldr  r0, =g_fan2; movs r1, #0; strb r1, [r0]
    ldr  r0, =g_state; movs r1, #STATE_MANUAL; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #2; strb r1, [r0]
    bl   draw_current_menu; b .Lhs_done
.Lhsf2b:
    @ sel=2: On
    ldr  r0, =g_fan2; movs r1, #1; strb r1, [r0]
    ldr  r0, =g_state; movs r1, #STATE_MANUAL; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #2; strb r1, [r0]
    bl   draw_current_menu

.Lhs_done:
    pop  {r4, r5, pc}

@ ----------------------------------------------------------------
@ dht11_read: bit-bang DHT11 on PA6
@ ----------------------------------------------------------------
.thumb_func
dht11_read:
    push {r4, r5, r6, r7, r8, lr}

    ldr  r6, =GPIOA_MODER
    ldr  r7, =GPIOA_BSRR
    ldr  r8, =GPIOA_IDR

    @ PA6 as output (MODER[13:12] = 01)
    ldr  r4, [r6]
    bic  r4, r4, #(3 << 12)
    orr  r4, r4, #(1 << 12)
    str  r4, [r6]

    @ Pull low 20 ms
    ldr  r0, =DHT_CLR; str r0, [r7]
    movs r0, #20; bl delay_ms

    @ Pull high 30 us then release to input
    ldr  r0, =DHT_PIN; str r0, [r7]
    movs r0, #30; bl delay_us
    ldr  r4, [r6]; bic r4, r4, #(3 << 12); str r4, [r6]

    @ Wait for DHT low response
    ldr  r5, =10000
.Ldht_wl:
    ldr  r4, [r8]; tst r4, #DHT_PIN; beq .Ldht_gl
    subs r5, r5, #1; bne .Ldht_wl; b .Ldht_fail
.Ldht_gl:
    ldr  r5, =10000
.Ldht_wh:
    ldr  r4, [r8]; tst r4, #DHT_PIN; bne .Ldht_gh
    subs r5, r5, #1; bne .Ldht_wh; b .Ldht_fail
.Ldht_gh:
    ldr  r5, =10000
.Ldht_wh2:
    ldr  r4, [r8]; tst r4, #DHT_PIN; beq .Ldht_bits
    subs r5, r5, #1; bne .Ldht_wh2; b .Ldht_fail

    @ Read 40 bits
.Ldht_bits:
    ldr  r0, =g_dht_buf
    movs r5, #5
    movs r3, #0
    movs r2, #8
.Ldht_nb:
    cmp  r5, #0; beq .Ldht_done
.Ldht_nbit:
    cmp  r2, #0; beq .Ldht_sb
    ldr  r4, =10000
.Ldht_wp:
    ldr  r1, [r8]; tst r1, #DHT_PIN; beq .Ldht_pe
    subs r4, r4, #1; bne .Ldht_wp; b .Ldht_fail
.Ldht_pe:
    ldr  r4, =10000
.Ldht_wp2:
    ldr  r1, [r8]; tst r1, #DHT_PIN; bne .Ldht_pe2
    subs r4, r4, #1; bne .Ldht_wp2; b .Ldht_fail
.Ldht_pe2:
    movs r4, #0
.Ldht_ch:
    ldr  r1, [r8]; tst r1, #DHT_PIN; beq .Ldht_hd
    add  r4, r4, #1
    ldr  r1, =2000; cmp r4, r1; bge .Ldht_fail
    b    .Ldht_ch
.Ldht_hd:
    lsls r3, r3, #1
    ldr  r1, =400; cmp r4, r1; blt .Ldht_bd
    orr  r3, r3, #1
.Ldht_bd:
    subs r2, r2, #1; b .Ldht_nbit
.Ldht_sb:
    strb r3, [r0], #1
    movs r3, #0; movs r2, #8
    subs r5, r5, #1; b .Ldht_nb

.Ldht_done:
    @ Verify checksum
    ldr  r0, =g_dht_buf
    ldrb r1, [r0, #0]; ldrb r2, [r0, #1]
    ldrb r3, [r0, #2]; ldrb r4, [r0, #3]; ldrb r5, [r0, #4]
    add  r1, r1, r2; add r1, r1, r3; add r1, r1, r4
    and  r1, r1, #0xFF; cmp r1, r5; bne .Ldht_fail
    @ Update globals
    ldr  r0, =g_dht_buf
    ldrb r1, [r0, #0]; ldr r2, =g_hum;  strb r1, [r2]
    ldrb r1, [r0, #2]; ldr r2, =g_temp; strb r1, [r2]
    bl   update_status; b .Ldht_exit

.Ldht_fail:
.Ldht_exit:
    ldr  r4, [r6]; bic r4, r4, #(3 << 12); str r4, [r6]
    pop  {r4, r5, r6, r7, r8, pc}

@ ----------------------------------------------------------------
@ init_gpio
@   PA0,PA1,PA4,PA6: input, pull-up
@   PB0,1,4,5,6,7: output
@   PA2/PA3 left alone (USART2 / ST-Link)
@ ----------------------------------------------------------------
.thumb_func
init_gpio:
    push {r4, r5, lr}

    @ Enable GPIOA + GPIOB clocks
    ldr  r4, =RCC_AHB1ENR; ldr r5, [r4]
    orr  r5, r5, #0x3; str r5, [r4]

    @ PA0,PA1,PA4,PA6 as input (clear MODER bits)
    @ clear mask: PA0[1:0]+PA1[3:2]+PA4[9:8]+PA6[13:12] = 0x330F
    ldr  r4, =GPIOA_MODER; ldr r5, [r4]
    ldr  r0, =0x330F; bic r5, r5, r0; str r5, [r4]

    @ PA0,PA1,PA4,PA6 pull-up
    @ set mask: 01 for each = 0x1105
    ldr  r4, =GPIOA_PUPDR; ldr r5, [r4]
    ldr  r0, =0x330F; bic r5, r5, r0
    ldr  r0, =0x1105; orr r5, r5, r0; str r5, [r4]

    @ PB0,1,4,5,6,7 as output
    ldr  r4, =GPIOB_MODER; ldr r5, [r4]
    ldr  r0, =0xFF0F; bic r5, r5, r0
    ldr  r0, =0x5505; orr r5, r5, r0; str r5, [r4]

    ldr  r4, =GPIOB_BSRR; ldr r5, =LCD_ALL_CLR; str r5, [r4]

    pop  {r4, r5, pc}

@ ----------------------------------------------------------------
@ setup
@ ----------------------------------------------------------------
.thumb_func
setup:
    push {lr}
    bl   init_gpio
    bl   lcd_init

    ldr  r0, =g_selection; movs r1, #1; strb r1, [r0]
    ldr  r0, =g_prev_clk;  movs r1, #1; strb r1, [r0]
    ldr  r0, =g_prev_sw;   movs r1, #1; strb r1, [r0]
    ldr  r0, =g_state;     movs r1, #STATE_HOME; strb r1, [r0]
    ldr  r0, =g_dht_timer; ldr r1, =DHT_INTERVAL; str r1, [r0]

    bl   dht11_read
    bl   draw_home
    pop  {pc}

@ ----------------------------------------------------------------
@ loop
@ ----------------------------------------------------------------
.thumb_func
loop:
    push {r4, r5, r6, r7, lr}

    @ Sample inputs
    ldr  r0, =GPIOA_IDR; ldr r0, [r0]
    and  r4, r0, #ENC_CLK              @ r4 = CLK raw
    and  r5, r0, #ENC_DT; lsr r5, r5, #1   @ r5 = DT  0 or 1
    and  r6, r0, #ENC_SW; lsr r6, r6, #4   @ r6 = SW  0 or 1

    ldr  r7, =g_prev_clk; ldrb r7, [r7]

    @ Dispatch on state
    ldr  r0, =g_state; ldrb r0, [r0]
    cmp  r0, #STATE_HOME; beq .Lloop_home

    @ ============================================================
    @ MENU STATES
    @ ============================================================

    @ Rotation: falling edge on CLK
    cmp  r7, #1; bne .Lmno_rot
    cmp  r4, #0; bne .Lmno_rot

    @ Get max items for current state
    ldr  r0, =g_state; ldrb r0, [r0]
    bl   get_max_items                 @ r0 = max
    movs r1, r0                        @ r1 = max (save)

    ldr  r0, =g_selection; ldrb r0, [r0]  @ r0 = current sel

    cmp  r5, #1; beq .Lmrot_dec

    @ CW: increment, clamp at max
    cmp  r0, r1; bge .Lmno_rot
    add  r0, r0, #1; b .Lmrot_save
.Lmrot_dec:
    @ CCW: decrement, clamp at 1
    cmp  r0, #1; ble .Lmno_rot
    sub  r0, r0, #1
.Lmrot_save:
    ldr  r1, =g_selection; strb r0, [r1]
    bl   draw_current_menu

.Lmno_rot:
    @ SW press: select item
    ldr  r0, =g_prev_sw; ldrb r0, [r0]
    cmp  r0, #1; bne .Lmno_sw
    cmp  r6, #0; bne .Lmno_sw
    bl   handle_select
.Lmno_sw:
    b    .Lloop_upd

    @ ============================================================
    @ HOME STATE
    @ ============================================================
.Lloop_home:
    @ SW press: enter main menu
    ldr  r0, =g_prev_sw; ldrb r0, [r0]
    cmp  r0, #1; bne .Lhno_sw
    cmp  r6, #0; bne .Lhno_sw
    ldr  r0, =g_state; movs r1, #STATE_MENU; strb r1, [r0]
    ldr  r0, =g_selection; movs r1, #1; strb r1, [r0]
    bl   draw_current_menu
    b    .Lloop_upd
.Lhno_sw:

    @ DHT timed read
    ldr  r0, =g_dht_timer; ldr r1, [r0]
    add  r1, r1, #1; str r1, [r0]
    ldr  r2, =DHT_INTERVAL; cmp r1, r2; blt .Lhno_dht
    movs r1, #0; str r1, [r0]
    bl   dht11_read
    bl   draw_home
.Lhno_dht:

.Lloop_upd:
    ldr  r0, =g_prev_clk; strb r4, [r0]
    ldr  r0, =g_prev_sw;  strb r6, [r0]
    movs r0, #5; bl delay_ms
    pop  {r4, r5, r6, r7, pc}

@ En0d of file