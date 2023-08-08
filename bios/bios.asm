; Very simple cpm68k bios
; Malcolm Harrow August 2023

; TO DO
; Change start positions of ram disks in read
; sort out org instruction
; Change MEMRGN
; Change disk parameter tables


; 7/29/17, fork from rev 3 of TinyBIOS for Tiny68000
; This BIOS assumes CPM15000 will be loaded
; It also assume the disk is reside in flash from location $420000 to $5FFFFF
; The disk already contains CP/M 68K distribution files


_ccp     equ $150BC                     ; hard location for _ccp of CPM15000.SR
  ;       org $1B000                     ; this is the hard location for _init for CPM15000.SR

_init::    
    move.l  #TRAPHNDL,$8c               ; set up trap #3 handler
    clr.l   D0                          ; log on disk A, user 0
    rts

TRAPHNDL:
; debug patch start
   ; move.l  D0,A4                    ; Save scratch registers
   ; move.l  D1,A5                    ; ...
   ; add.l   #67,D1                      ; print from 'B' onwards
   ; jsr     CONOUT
   ; move.l  A4,D0                    ; Restore scratch registers
   ; move.l  A5,D1                    ; ...
; debug patch end

    cmpi    #23,D0                      ; Function call in range ?
    bcc     TRAPNG
    add.l   D0,D0                       ; Multiply FC...
    add.l   D0,D0                       ; ... by 4...
    move.l  BIOSBASE(PC,D0),A0          ; ... and calc offset into table...
    jsr     (A0)                        ; ... then jump there

TRAPNG:
    rte

BIOSBASE:
    dc.l    _init
    dc.l    WBOOT
    dc.l    CONSTAT
    dc.l    CONIN
    dc.l    CONOUT
    dc.l    LSTOUT
    dc.l    PUN
    dc.l    RDR
    dc.l    HOME
    dc.l    SELDSK
    dc.l    SETTRK
    dc.l    SETSEC
    dc.l    SETDMA
    dc.l    READ
    dc.l    WRITE
    dc.l    LISTST
    dc.l    SECTRAN
    dc.l    SETDMA
    dc.l    GETSEG
    dc.l    GETIOB
    dc.l    SETIOB
    dc.l    FLUSH
    dc.l    SETEXC


WBOOT:  
    jmp   _ccp

CONSTAT: 
; Check for keyboard input. Set d0 to 1 if keyboard input is pending, otherwise set to 0.
    move.b #7,D0                        ; use EASy68k trap 15 task 7
    trap   #15                          ; d1.b = 1 if keyboard ready, otherwise = 0
    clr.l  D0
    move.b D1,D0
    rts
         
CONIN:    
; Read single ASCII character from the keyboard into d0
    bsr    CONSTAT                      ; see if key pressed
    tst    D0
    beq    CONIN
    move.b #5,D0                        ; use EASy68k trap 15 task 5
    trap   #15                          ; d1.b contains the ascii character
    move.b D1,D0      
    and.l  #$7f,D0                      ; only use 7 bit character set
    rts

CONOUT: 
; Display single ASCII character in d1
    move.b #6,D0                        ; use EASy68k trap 15 task 6
    trap   #15
    rts                                 ; and exit

LSTOUT:    
PUN:
RDR:
    rts

LISTST:    
    move.b #$ff,D0
    rts

MAXDSK     equ 3                         ; three RAM drives
DPHLEN     equ 26                        ; length of disk parameter header

HOME:    
    clr.b  TRACK
    rts

SELDSK:    
;    select disk given by register d1.b
    moveq  #0,D0
    cmp.b  #MAXDSK,D1                     ; valid drive number?
    bpl    SELRTN                         ; if no, return 0 in d0
    move.b D1,SELDRV                      ; else, save drive number
    move.b SELDRV,D0
    mulu   #DPHLEN,D0
    add.l  #DPH0,D0                       ; point d0 at correct dph

SELRTN:
    rts

SETTRK:    
    move.w  D1,TRACK
    rts

SETSEC:    
    move.w  D1,SECTOR
    rts

SECTRAN:
;    no sector translate, put d1 into d0 and return
    move.w  D1,D0
    rts

SETDMA:
    move.l  D1,DMA
    rts

READ:
; Read one sector from requested disk, track, sector to dma address
; Both drive A, B & C are RAM drives
; drive A starts from 0x420000 to 0x5BFFFF
; drive B starts from 0xC0000 to 0xFFFFF


    bsr     SETUPRD                      ; translate track/sector values into RAM loc
RAMDRVR:
    move.l (A0)+,(A1)+
    dbra   D2,RAMDRVR

    clr.l  D0                            ; return OK status         
    rts         

SETUPRD:
; translate track/sector into RAM location on the RAM drive
    move.l TRACK,D0                      ; get track & sector values
    lsl.w  #6,D0                         ; multiply by 64
    lsl.l  #1,D0                         ; multiply the track/sector by 128 to index into RAM
    cmp.b  #2,SELDRV                     ; drive C is RAM drive
    beq    RAMDRV
; now have one drive starting at 0x20000
;    add.l  #$420000,D0                   ; add base address of RAM drive
    add.l  #$20000,D0                   ; add base address of RAM drive
    bra    GETDATA

RAMDRV:
; no drive C
;    add.l  #$C0000,D0

GETDATA:
    move.l D0,A0                         ; point to the track/sector in RAM drive
    move.l DMA,A1                        ; get dma
    move.w #(128/4)-1,D2                 ; long word move 128 bytes of sector data
    rts

WRITE:
; Write one sector to requested disk, track, sector from dma address
; Both drive A & B are RAM drive
    cmp.b  #2,SELDRV                     ; only drive C can be written
    bne    WRBAD
    bsr    SETUPRD                       ; translate track/sector values into RAM loc
RAMDRVW:
    move.l (A1)+,(A0)+
    dbra   D2,RAMDRVW

    clr.l  D0
    rts         
WRBAD:
    move.l #-1,D0
    rts

FLUSH:
    clr.l  D0                            ; return successful
    rts

GETSEG:
    move.l #MEMRGN,D0                    ; return address of mem region table
    rts

GETIOB:
    rts

SETIOB:
    rts

SETEXC:
    andi.l  #$ff,D1                      ; do only for exceptions 0 - 255
    cmpi    #47,D1
    beq     NOSET                        ; this BIOS doesn't set Trap 15
    cmpi    #9,D1                        ; or Trace
    beq     NOSET
    lsl     #2,D1                        ; multiply exception nmbr by 4
    movea.l D1,A0
    move.l  (A0),D0                      ; return old vector value
    move.l  D2,(A0)                      ; insert new vector

NOSET:    
    rts

* ************************************************************************** *
; Data
* ************************************************************************** *

SELDRV        dc.b        $ff            ; drive requested by seldsk
RESV          dc.b        0              ; reserve byte, padding
CURCFSECT     dc.l        -1             ; current CF sector, the 512 bytes data of curtrk is in sectCF
TRACK         dc.w        0              ; track requested by settrk
SECTOR        dc.w        0              ; max sector value is 0x3FF
DMA           dc.l        0
SELCODE       dc.b        0              ; reserve byte
RESV1         dc.b        0              ; reserve byte, padding

; memory table must start on an even address
              even
MEMRGN        dc.w        1              ; 1 memory region
;              dc.l        $20000         ; right after the CP/M 
              dc.l        $02000         ; right after the rosco firmware 
              dc.l        $13000         ; goes until $13000, 256K bytes
;			  dc.l        $A0000         ; goes until $C0000, 655K bytes  

; disk parameter headers

DPH0:    
    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV0                       ; ptr to allocation vector

DPH1:
    dc.l     0                           ; no sector translation table
    dc.w     0                           ; dummy
    dc.w     0
    dc.w     0
    dc.l     DIRBUF                      ; ptr to directory buffer
    dc.l     DPB1                        ; ptr to disk parameter block
    dc.l     0                           ; permanent drive, no check vector
    dc.l     ALV1                        ; ptr to allocation vector

DPH2:
    dc.l     0                           ; no sector translation table
    dc.w     0                           ; dummy
    dc.w     0
    dc.w     0
    dc.l     DIRBUF                      ; ptr to directory buffer
    dc.l     DPB2                        ; ptr to disk parameter block
    dc.l     0                           ; permanent drive, no check vector
    dc.l     ALV2                        ; ptr to allocation vector

; disk parameter block
; flash drive from $420000 to 59FFFF,
; choose a BLS of 2048
; 1024 sectors (128 byte sector) per track
; 16 sectors per block
; 12 tracks per drive 
; DPB0:    
;     dc.w     1024                        ; 1024 sectors per track
;     dc.b     4                           ; block shift for BLS of 2048
;     dc.b     15                          ; block mask for BLS of 2048
;     dc.b     0                           ; extent mask, EXM
;     dc.b     0                           ; dummy fill
;     dc.w     767                         ; DSM, (12 tracks * 1024 sectors * 128 bytes /2048)-1
                           
;     dc.w     255                         ; DRM, 256 directory entries
;     dc.w     0                           ; directory mask
; 	dc.w     0                           ; permanent mounted drive, check size is zero
;     dc.w     0                           ; no track offset

; hack in a drive 0 that looked like old drive 1
DPB0:    
    dc.w     1024                        ; 1024 sectors per track
    dc.b     4                           ; block shift for BLS of 2048
    dc.b     15                          ; block mask for BLS of 2048
    dc.b     0                           ; extent mask, EXM
    dc.b     0                           ; dummy fill
    dc.w     191                         ; DSM, (3 tracks * 1024 sectors * 128 bytes /2048)-1
                           
    dc.w     255                         ; DRM, 256 directory entries
    dc.w     0                           ; directory mask
    dc.w     0                           ; permanent mounted drive, check size is zero
    dc.w     12                          ; no track offset


; flash drive from $5A0000 to $5FFFFF
; choose a BLS of 2048
; 1024 sectors (128 byte sector) per track
; 16 sectors per block
; 3 tracks per drive 
DPB1:    
    dc.w     1024                        ; 1024 sectors per track
    dc.b     4                           ; block shift for BLS of 2048
    dc.b     15                          ; block mask for BLS of 2048
    dc.b     0                           ; extent mask, EXM
    dc.b     0                           ; dummy fill
    dc.w     191                         ; DSM, (3 tracks * 1024 sectors * 128 bytes /2048)-1
                           
    dc.w     255                         ; DRM, 256 directory entries
    dc.w     0                           ; directory mask
    dc.w     0                           ; permanent mounted drive, check size is zero
    dc.w     12                          ; no track offset
         
; use the battery-back RAM in ADC MPU as small RAMdisk, $C0000-$FFFFF
; disk parameter block
; choose a BLS of 1024
; 1024 sectors (128 byte sector) per track
; 8 sectors per block
; 2 tracks per drive 
DPB2:    
    dc.w     1024                        ; 1024 sectors per track
    dc.b     3                           ; block shift for BLS of 1024
    dc.b     7                           ; block mask for BLS of 1024
    dc.b     0                           ; extent mask, EXM
    dc.b     0                           ; dummy fill
    dc.w     255                         ; DSM, (2 tracks * 1024 sectors * 128 bytes /2048)-1
; force the block number to be words rather than bytes                           
    dc.w     127                         ; DRM, 128 directory entries
    dc.w     0                           ; directory mask
    dc.w     0                           ; permanent mounted drive, check size is zero
    dc.w     0                           ; no track offset

**X    .bss

DIRBUF:    
    ds.b     128                         ; directory buffer

ALV0:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128
ALV1:    
	ds.b     256                         ; DSM/8 +1 = 128, round up to 256
ALV2:    
	ds.b     256                         ; DSM/8 +1 = 128, round up to 256
