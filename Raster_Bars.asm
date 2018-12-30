#import "helpers.asm"

.label border = $d020
.label background = $d021

.label cia1_interrupt_control_register = $dc0d
.label cia2_interrupt_control_register = $dd0d

// The animation skips these many frames in between 'active' frames:
// 0 means "max animation speed", for instance 50 Hz on PAL, and 60 on NTSC.
// 1 means "display one frame then repeat the next": the animation is 25 Hz on PAL.
.const ANIMATION_SKIP_THESE_MANY_FRAMES = 1
.const FROM_RASTER_LINE_INDEX = 16 // must be at least 3
.const SUB_BAR_COLOR_THICKNESS = 3
.const TO_RASTER_LINE_INDEX = 35 // FIXME: 50 - (SUB_BAR_COLOR_THICKNESS*5)
.const RASTER_LINE = FROM_RASTER_LINE_INDEX-2-1
.const SPRITE_BITMAPS = 255-8

:BasicUpstart2(main)
main:
  sei
    clear_screen(96) // 96 is the code for the ' ' character
    lda #BLACK
    sta border
    lda #WHITE
    sta background

    // counter for frame rate limiting purposes
    lda #0
    sta $fc

    // 1 == increase $fe (0 would decrease $fe)
    lda #1
    sta $fd

    // Relative raster line index: it is 0 when it starts from FROM_RASTER_LINE_INDEX
    // and it ends up at the difference of (TO_RASTER_LINE_INDEX-FROM_RASTER_LINE_INDEX)
    // when it reaches TO_RASTER_LINE_INDEX.
    lda #0
    sta $fe

    lda $01
    and #%11111101
    sta $01

    lda #%01111111
    sta cia1_interrupt_control_register
    sta cia2_interrupt_control_register
    lda cia1_interrupt_control_register
    lda cia2_interrupt_control_register

    lda #%00000001
    sta vic2_interrupt_control_register
    sta vic2_interrupt_status_register
    :set_raster(RASTER_LINE)
    :mov16 #irq1 : $fffe
  cli

loop:
  jmp loop

irq1:
  sta atemp
  stx xtemp
  sty ytemp

  ldy $fe          // (3)
  :stabilize_irq() // RL[13:14]
  // The -3 below at RL15 is to compensate for the 3-cycle delay after stabilize_irq().
  // Also an additional -7 is for the extra cycles (2+2+3) when bne go_lower below fails.
  cycles(-3+63) // RL15

  /* here we are at the exact start of the FROM_RASTER_LINE_INDEX raster line */

  // skip TO_RASTER_LINE_INDEX-FROM_RASTER_LINE_INDEX BLACK raster lines
ld_y_above: // RL16
  cpy #TO_RASTER_LINE_INDEX-FROM_RASTER_LINE_INDEX // 2  \
  bne go_lower                                     // 3_2 |-> 2+2+3 is the -7 at RL15.
  cycles(63-2-2-3-6) // The last -6 is to set RED below in draw_colored_lines.
  jmp draw_colored_lines                           // 3  /
go_lower:
  iny                                              // 2
  cycles(63-2-3-2-3)
  jmp ld_y_above                                   // 3

  /* here we are at the exact start of the current raster line */

draw_colored_lines:
  //Display raster lines in the upper border.
  lda #RED        // 2
  sta border      // 4
  cycles(SUB_BAR_COLOR_THICKNESS*63 - 6)

  lda #ORANGE     // 2
  sta border      // 4
  cycles(SUB_BAR_COLOR_THICKNESS*63 - 6)

  lda #YELLOW     // 2
  sta border      // 4
  cycles(SUB_BAR_COLOR_THICKNESS*63 - 6)

  lda #GREEN      // 2
  sta border      // 4
  cycles(SUB_BAR_COLOR_THICKNESS*63 - 6)

  lda #BLUE       // 2
  sta border      // 4
  cycles(SUB_BAR_COLOR_THICKNESS*63 -6)

  // Set border color back to BLACK.
  // Skip the cycles for the 200 raster lines in the background area.
  lda #BLACK      // 2 \ _ final -6
  sta border      // 4 /   cycles above

  // Wait for 19 good lines because
  // TO_RASTER_LINE_INDEX-FROM_RASTER_LINE_INDEX == (50-3*5) - 16 == 19. 
  jsr wait_6_good_lines_minus_jsr_and_rts
  jsr wait_6_good_lines_minus_jsr_and_rts
  jsr wait_6_good_lines_minus_jsr_and_rts
  jsr wait_one_good_line

  jsr wait_8_rows_with_20_cycles_bad_lines
  jsr wait_8_rows_with_20_cycles_bad_lines
  jsr wait_8_rows_with_20_cycles_bad_lines
  jsr wait_one_bad_line_minus_3
  jsr wait_6_good_lines_minus_jsr_and_rts
  :cycles(63-6) // The last -6 is to set RED below.

  //Display raster lines in the lower border.
  lda #RED        // 2
  sta border      // 4
  cycles(SUB_BAR_COLOR_THICKNESS*63 - 6)

  lda #ORANGE     // 2
  sta border      // 4
  cycles(SUB_BAR_COLOR_THICKNESS*63 - 6)

  lda #YELLOW     // 2
  sta border      // 4
  cycles(SUB_BAR_COLOR_THICKNESS*63 - 6)

  lda #GREEN      // 2
  sta border      // 4
  cycles(SUB_BAR_COLOR_THICKNESS*63 - 6)

  lda #BLUE       // 2
  sta border      // 4
  cycles(SUB_BAR_COLOR_THICKNESS*63 - 6)

  // Set border color back to BLACK.
  lda #BLACK      // 2
  sta border      // 4


  // Update animation every 10 frames
  lda $fc
  cmp #ANIMATION_SKIP_THESE_MANY_FRAMES
  beq reset_fc
  inc $fc
  jmp exiting_irq
reset_fc:
  lda #0
  sta $fc

  // Update initial delay
adjust_initial_delay:
  // increase $fe up to TO_RASTER_LINE_INDEX-FROM_RASTER_LINE_INDEX and then back to 0.
  lda $fd // 1 == increment $fe, 0 == decrement $fe
  beq decrease_fe
increase_fe:
  lda $fe 
  cmp #TO_RASTER_LINE_INDEX-FROM_RASTER_LINE_INDEX
  beq make_fd_zero
  inc $fe
  jmp exiting_irq
  make_fd_zero:
  lda #0 // start decreasing $fe
  sta $fd
  jmp exiting_irq
decrease_fe:
  lda $fe
  beq make_fd_one
  dec $fe
  jmp exiting_irq
  make_fd_one:
  lda #1
  sta $fd


exiting_irq:
  asl vic2_interrupt_status_register
  :set_raster(RASTER_LINE)
  :mov16 #irq1 : $fffe
  lda atemp: #$00
  ldx xtemp: #$00
  ldy ytemp: #$00
  rti

/*
 * Wait functions.
*/

// Waits 23 cycles minus 12 cycles for the caller's jsr and this function's rts.
wait_one_bad_line: //+6
  :cycles(-6+23-6) // 23-12
  rts //+6
wait_one_bad_line_minus_3: //+6
  :cycles(-6+23-3-6) //20-12
  rts //+6

// Waits 63 cycles minus 12 cycles for the caller's jsr and this function's rts.
wait_one_good_line: //+6
  :cycles(-6+63-6) // 63-12
  rts //+6

// Waits 63 cycles minus 12 cycles for the caller's jsr and this function's rts, and
// further minus 12 cycles for the caller's caller's jsr and corresponding rts.
// Basically this wait function is meant to be called from another wait function.
wait_one_good_line_minus_jsr_and_rts: //+6
  :cycles(-6-6+63-6-6) // 63-24
  rts //+6

// Waits 63 cycles minus 12 cycles for the caller's jsr and this function's rts, and
// further minus 12 cycles for the caller's caller's jsr and corresponding rts.
// Basically this wait function is meant to be called from another wait function.
wait_6_good_lines_minus_jsr_and_rts: //+6
  jsr wait_one_good_line // 1: 63-12+6+6 = 63
  jsr wait_one_good_line // 2: 63-12+6+6 = 63
  jsr wait_one_good_line // 3: 63-12+6+6 = 63
  jsr wait_one_good_line // 4: 63-12+6+6 = 63
  jsr wait_one_good_line // 5: 63-12+6+6 = 63
  // 6: Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 6: 63-12
  rts //+6

// wait one entire row worth of cycles minus the 12 cycles to call this function.
wait_1_row_with_20_cycles_bad_line: //+6
  jsr wait_one_bad_line_minus_3 // 23-3 = 20
  jsr wait_6_good_lines_minus_jsr_and_rts // 63*5 + 63-12+6+6 = 63*6
  // Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 63-12
  rts //+6

// wait two full rows worth of cycles minus the 12 cycles to call this function.
wait_2_rows_with_20_cycles_bad_lines: //+6
  jsr wait_1_row_with_20_cycles_bad_line
  jsr wait_one_bad_line_minus_3 // 23-3 = 20
  jsr wait_6_good_lines_minus_jsr_and_rts // 63*5 + 63-12+6+6 = 63*6
  // Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 63-12
  rts //+6

wait_4_rows_with_20_cycles_bad_lines: //+6
  jsr wait_2_rows_with_20_cycles_bad_lines
  jsr wait_1_row_with_20_cycles_bad_line
  jsr wait_one_bad_line_minus_3 // 23-3 = 20
  jsr wait_6_good_lines_minus_jsr_and_rts // 63*5 + 63-12+6+6 = 63*6
  // Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 63-12
  rts //+6

wait_8_rows_with_20_cycles_bad_lines: //+6
  jsr wait_4_rows_with_20_cycles_bad_lines
  jsr wait_2_rows_with_20_cycles_bad_lines
  jsr wait_1_row_with_20_cycles_bad_line
  jsr wait_one_bad_line_minus_3 // 23-3 = 20
  jsr wait_6_good_lines_minus_jsr_and_rts // 63*5 + 63-12+6+6 = 63*6
  // Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 63-12
  rts //+6