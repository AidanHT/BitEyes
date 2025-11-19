# Pin Assignment Script for PS/2 Mouse VGA Drawing System
# Target: DE1-SoC Board (Cyclone V 5CSEMA5F31C6)
# Usage: In Quartus Prime, go to Tools -> Tcl Scripts and run this file
# Or use command: quartus_sta -t DE1_SoC_pin_assignments.tcl

# Clock and Reset
set_location_assignment PIN_AF14 -to CLOCK_50
set_location_assignment PIN_AA14 -to KEY[0]
set_location_assignment PIN_AA15 -to KEY[1]
set_location_assignment PIN_W15 -to KEY[2]
set_location_assignment PIN_Y16 -to KEY[3]

# Switches
set_location_assignment PIN_AB12 -to SW[0]
set_location_assignment PIN_AC12 -to SW[1]
set_location_assignment PIN_AF9 -to SW[2]
set_location_assignment PIN_AF10 -to SW[3]
set_location_assignment PIN_AD11 -to SW[4]
set_location_assignment PIN_AD12 -to SW[5]
set_location_assignment PIN_AE11 -to SW[6]
set_location_assignment PIN_AC9 -to SW[7]
set_location_assignment PIN_AD10 -to SW[8]
set_location_assignment PIN_AE12 -to SW[9]

# PS/2 Port (J7 - Mouse)
set_location_assignment PIN_AA8 -to PS2_CLK
set_location_assignment PIN_AB8 -to PS2_DAT
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to PS2_CLK
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to PS2_DAT
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to PS2_CLK
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to PS2_DAT

# VGA Red
set_location_assignment PIN_AA1 -to VGA_R[0]
set_location_assignment PIN_V1 -to VGA_R[1]
set_location_assignment PIN_Y2 -to VGA_R[2]
set_location_assignment PIN_Y1 -to VGA_R[3]
set_location_assignment PIN_W1 -to VGA_R[4]
set_location_assignment PIN_T2 -to VGA_R[5]
set_location_assignment PIN_R1 -to VGA_R[6]
set_location_assignment PIN_R2 -to VGA_R[7]

# VGA Green
set_location_assignment PIN_P1 -to VGA_G[0]
set_location_assignment PIN_T1 -to VGA_G[1]
set_location_assignment PIN_U1 -to VGA_G[2]
set_location_assignment PIN_U2 -to VGA_G[3]
set_location_assignment PIN_V2 -to VGA_G[4]
set_location_assignment PIN_W2 -to VGA_G[5]
set_location_assignment PIN_AA2 -to VGA_G[6]
set_location_assignment PIN_AB2 -to VGA_G[7]

# VGA Blue
set_location_assignment PIN_AC2 -to VGA_B[0]
set_location_assignment PIN_AD2 -to VGA_B[1]
set_location_assignment PIN_AE2 -to VGA_B[2]
set_location_assignment PIN_AF2 -to VGA_B[3]
set_location_assignment PIN_Y3 -to VGA_B[4]
set_location_assignment PIN_AA3 -to VGA_B[5]
set_location_assignment PIN_AB3 -to VGA_B[6]
set_location_assignment PIN_AC3 -to VGA_B[7]

# VGA Control Signals
set_location_assignment PIN_AD12 -to VGA_HS
set_location_assignment PIN_AC12 -to VGA_VS
set_location_assignment PIN_AE12 -to VGA_BLANK_N
set_location_assignment PIN_AF12 -to VGA_SYNC_N
set_location_assignment PIN_W12 -to VGA_CLK

# LEDs
set_location_assignment PIN_V16 -to LEDR[0]
set_location_assignment PIN_W16 -to LEDR[1]
set_location_assignment PIN_V17 -to LEDR[2]
set_location_assignment PIN_V18 -to LEDR[3]
set_location_assignment PIN_W17 -to LEDR[4]
set_location_assignment PIN_W19 -to LEDR[5]
set_location_assignment PIN_Y19 -to LEDR[6]
set_location_assignment PIN_W20 -to LEDR[7]
set_location_assignment PIN_W21 -to LEDR[8]
set_location_assignment PIN_Y21 -to LEDR[9]

# HEX0
set_location_assignment PIN_AE26 -to HEX0[0]
set_location_assignment PIN_AE27 -to HEX0[1]
set_location_assignment PIN_AE28 -to HEX0[2]
set_location_assignment PIN_AG27 -to HEX0[3]
set_location_assignment PIN_AF28 -to HEX0[4]
set_location_assignment PIN_AG28 -to HEX0[5]
set_location_assignment PIN_AH28 -to HEX0[6]

# HEX1
set_location_assignment PIN_AJ29 -to HEX1[0]
set_location_assignment PIN_AH29 -to HEX1[1]
set_location_assignment PIN_AH30 -to HEX1[2]
set_location_assignment PIN_AG30 -to HEX1[3]
set_location_assignment PIN_AF29 -to HEX1[4]
set_location_assignment PIN_AF30 -to HEX1[5]
set_location_assignment PIN_AD27 -to HEX1[6]

# HEX2
set_location_assignment PIN_AB23 -to HEX2[0]
set_location_assignment PIN_AE29 -to HEX2[1]
set_location_assignment PIN_AD29 -to HEX2[2]
set_location_assignment PIN_AC28 -to HEX2[3]
set_location_assignment PIN_AD30 -to HEX2[4]
set_location_assignment PIN_AC29 -to HEX2[5]
set_location_assignment PIN_AC30 -to HEX2[6]

# HEX3
set_location_assignment PIN_AD26 -to HEX3[0]
set_location_assignment PIN_AC27 -to HEX3[1]
set_location_assignment PIN_AD25 -to HEX3[2]
set_location_assignment PIN_AC25 -to HEX3[3]
set_location_assignment PIN_AB28 -to HEX3[4]
set_location_assignment PIN_AB25 -to HEX3[5]
set_location_assignment PIN_AB22 -to HEX3[6]

# I/O Standards
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CLOCK_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to KEY[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDR[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX0[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX1[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX2[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX3[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_R[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_G[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_B[*]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_HS
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_VS
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_BLANK_N
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_SYNC_N
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_CLK

# Current Strength Settings for better signal integrity
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to VGA_R[*]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to VGA_G[*]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to VGA_B[*]
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to VGA_HS
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to VGA_VS
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to VGA_BLANK_N
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to VGA_SYNC_N
set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to VGA_CLK

# Slew Rate Settings
set_instance_assignment -name SLEW_RATE 2 -to VGA_R[*]
set_instance_assignment -name SLEW_RATE 2 -to VGA_G[*]
set_instance_assignment -name SLEW_RATE 2 -to VGA_B[*]
set_instance_assignment -name SLEW_RATE 2 -to VGA_HS
set_instance_assignment -name SLEW_RATE 2 -to VGA_VS
set_instance_assignment -name SLEW_RATE 2 -to VGA_CLK

puts "Pin assignments completed successfully!"
puts "Total pins assigned: [llength [get_all_assignments -name LOCATION -type pin]]"

