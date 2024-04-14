; *--------------------------------------------------------------------------------
; * Load the srec file and jump to the start point to boot cpm68k
; * Malcolm Harrow March 2022 to August 2023 !!!  https://github.com/harrowm
; *--------------------------------------------------------------------------------

                    section .text

kmain::
                    LEA.L   strBootMsg,A0
                    MOVE.L  A0,-(A7)
                    JSR     mcPrintln
                    ADDQ.L  #4,A7

                    ; relocate the cpm srec file to $15000
                    LEA.L   srec_start,A0                  ; start of srec file
                    LEA.L   $15000,A1                      ; absolute dest addr (CPM start)
                    MOVE.L  #(srec_end-srec_start)/4-1,d0
.MOVE_LOOP:
                    MOVE.L  (A0)+,(A1)+                    ; copy long word from source to dest
                    DBRA    D0,.MOVE_LOOP                  ; loop until end of srec

                    ; relocate the bios srec file to $1B000
                    LEA.L   bios_start,A0                  ; start of srec file
                    LEA.L   $1B000,A1                      ; absolute dest addr (standard BIOS start for CPM at 150000)
                    MOVE.L  #(bios_end-bios_start)/4-1,d0  
.MOVE_LOOP2:
                    MOVE.L  (A0)+,(A1)+                    ; copy long word from source to dest
                    DBRA    D0,.MOVE_LOOP2                 ; loop until end of srec


                    ; Rather than load an image into memory,l set up a blank one
                    ; We choose to load at 0xC0000 and make it 128k in size .. 0x20000
                    ; A blank CPM disk is full of 0xE5 characters

                    lea.l    $C0000,A1
                    move.l   #($20000/4)-1,D0
.MOVE_LOOP3:
                    move.l   #$E5E5E5E5,(A1)+
                    dbra     D0,.MOVE_LOOP3

                    ; and jump to it to start CPM !
                    JMP     $15000                                      
                    RTS                                                 

                    align 4
srec_start:         incbin "../cpmfs/target/boot15k.sr.bin"
srec_end:      
                    align 4
bios_start:         incbin "../bios/target/bios.sr.bin" 
bios_end:      

strBootMsg:         dc.b   "CPM-68k loader for rosco_m68k v0.5", 0
