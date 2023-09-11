; Very simple cpm68k bios
; Malcolm Harrow August 2023

_ccp               equ $150BC                           ; hard location for _ccp of CPM15000.SR
ramDriveLocation   equ $C0000                           ; memory location for RAM drive
DEBUG              set 0                                ; set to 1 to print debug messgae, 0 turns off

; move 128 bytes from A0 to A1 as quickly as possible
; obviously the downside is that this trashes D0-D7 and A2-A5 :o                                      
copyData MACRO
    movem.l (A0)+,D0-D7/A2-A5                           ; 12 long words
    movem.l D0-D7/A2-A5,(A1)
    adda.w  #48,A1                                      ; 12 * 4
    movem.l (A0)+,D0-D7/A2-A5                               
    movem.l D0-D7/A2-A5,(A1)
    adda.w  #48,A1
    movem.l (A0)+,D0-D7                                 ; 8 long words, so 12+12+8=32
    movem.l D0-D7,(A1)
ENDM    

; pass in a character to this routine to specify type of operation on the sector eg 'R' or 'W'
debugPrintSector MACRO
    IFNE DEBUG
        movem.l D0-D3/A0-A3,-(A7)

        moveq.l #6,D0                                   
        move.b  #\1,D1                                     
        trap    #15
    
        moveq.l #15,D0
        move.l  (lastFATSector),D1                          ; sector in hex
        move.b  #16,D2
        trap    #15

        moveq.l #6,D0
        move.b  #'-',D1                                    
        trap    #15

        moveq.l #15,D0
        move.l  D3,D1                                       ; offset on sector in hex
        move.b  #16,D2
        trap    #15

        moveq.l #6,D0
        move.b  #' ',D1                                     
        trap    #15

        movem.l (A7)+,D0-D3/A0-A3
    ENDIF
ENDM

; pass in a character to this routine to specify type of operation on the RAM drive eg 'R' or 'W'
; Assuem A0 is already set up to point to the RAM being moved
debugPrintRAM MACRO
    IFNE DEBUG
        movem.l D0-D3/A0-A3,-(A7)

        exg     A0,A3                                       ; save A0 as trap 15 trashes it
        moveq.l #6,D0                                   
        move.b  #\1,D1                                     
        trap    #15
        exg     A3,A0

        moveq.l #15,D0
        move.l  A0,D1                                       ; address in hex
        move.b  #16,D2
        trap    #15

        moveq.l #6,D0
        move.b  #' ',D1                                     
        trap    #15

        movem.l (A7)+,D0-D3/A0-A3
    ENDIF
ENDM

_init::    
    ; at this stage, we have loaded from the SDCARD, so we know its valid, no need to re-init
    ; need to find the starting block of the CPM disk image on the sd card, or offset
    ; to do this we will trawl through the FAT32 boot record etc

    ; to do this:
    ;   - read the MBR, block 0 and note:
    ;     - number of reserved sectors, 0x0E, word (eg 20 00)
    ;     - logical sectors per FAT, 0x24, long  (eg f1 03 00 00)
    ;     - number of fats, 0x10, byte (eg 02)
    ;   - This enables us to calculate:
    ;     - start of FAT table (sector after number of reserved sectors - 32 or 0x4000
    ;     - start of root directory,  Logical sectors per FAT (0x24) * Number of FATs (0x10) + Reserved logical sectors (0xe) = 0x802 or 0x100400
    ;   - The root directory is arranged 32 bytes per entry.  We will assume our CPM disk image is in the root and called cpmdisk.img.  So 16 entries in a 512 byte sector
    
    ; check sd card support
    moveq.l #0,D0
    trap    #13
    cmp.l   #$1234FEDC,D0                               ; check magic return
    beq     .haveSDsupport
    lea     msgNoSdCardSupport,A0
    jmp     .errExit
    
.haveSDsupport:
    ; init the sd card and get sd card structure back
    lea     sd,A1
    moveq.l #1,D0                                       
    trap    #13
    cmp.l   #0,D0                                       ; check return
    beq     .haveSDinit
    lea     msgNoSdCardInit,A0
    jmp     .errExit

.haveSDinit:
    ; read the MBR from sector 0 so we can calculate position of the MBR and root diectory in the CPM image
    lea     sd,A1
    moveq.l #2,D0                                       ; read the MBR from the sd card 
    moveq.l #0,D1                                       ; sector number to read
    lea     sdBuf,A2
    trap    #13
    cmp.l   #0,D0                                       ; check return
    bne     .haveReadMBR
    lea     msgNoSdCardRead,A0
    jmp     .errExit

.haveReadMBR:
    move.w  $e+sdBuf,D6                                 ; number of reserved sectors from MBR.  Reversed due to endianess of 68000
    rol.w   #8,D6
    move.w  D6,startFAT

    move.l  $24+sdBuf,D6
    rol.w   #8,D6
    swap    D6
    rol.w   #8,D6
    move.w  D6,rootDirectorySector
    
    moveq.l #0,D6                                       ; multiply by number of FAT tables
    move.b  $10+sdBuf,D6

    mulu.w  rootDirectorySector,D6
    add.w   startFAT,D6
    move.w  D6,rootDirectorySector


;    - logical sectors per FAT, 0x24, long  (eg f1 03 00 00)

;    sector = sector of start of root directory
;    entry = 0
;    while (1) {
;      offset = entry % 16
;      if offset == 0 {
;        // read next sector
;        read next sector
;        increment sector
;      };;
;
;      directory_entry = offset * 32 plus buffer start
;
;      if directory_entry[0] == 0 { // end of root directory
;        message failure
;        return failure
;      }
;
;      if directory_entry[0xb] & 0x10 { // subdirectory
;        continue
;      }
;
;      if directory entry[0xb] == 0xf { // record contains a long file name
;        continue
;      }
;
;      if strncmp(directory entry, "CPMDISK IMG", 11) {
;        // found file, might have to ignore case here, lets see
;        // record sector file starts and file length
;        block = entry[20,21] << 16 + entry[26,27]
;        // both of these are store lsb first eg length of 0x7e84 is stored 84 7e 00 00
;        return success
;      }
;      entry++
;    }


    ; search the FAT to try to find the CPM disk image
    moveq.l #0,D3                                       ; sector to read
    moveq.l #0,D4                                       ; directory entry in sector.  Sector is 512b, directory table is 32b so 16 directories per sector

.startDirectoryEntry:
    move.l  D4,D5
    and.l   #15,D5                                      ; only look at last 4 bits, we want to calculate (directory entry % 16)
    bne     .noReadRequired                             ; we dont need to read a new sector from the sd card

    ; read the MBR from sector 0 so we can calculate position of the MBR and root diectory in the CPM image
    lea     sd,A1
    moveq.l #2,D0                                       ; read sector trap
    move.w  rootDirectorySector,D1
    add.w   D3,D1                                       ; sector number to read plus offset to rootDirectorySector
    lea     sdBuf,A2
    trap    #13
    cmp.l   #0,D0                                       ; check return
    bne     .noReadError
    lea     msgNoSdCardRead,A0
    jmp     .errExit

.noReadError:
    addq.l  #1,D3                                       ; increment next sector to read
    moveq.l #0,D4                                       ; reset directory entry to zero 

.noReadRequired:
    move.l  D4,D5                                       ; D4 contains directory record
    lsl.l   #5,D5                                       ; multiply offset by 32 to get to start of directory record
    add.l   #sdBuf,D5
    movea.l D5,A5
    move.b  (A5),D6
    tst.b   D6                                          ; reached end of root directory entries
    bne     .notDirEnd
    lea     msgNoCPMImage,A0
    jmp     .errExit

.notDirEnd:
    move.b  $b(A5),D6
    cmp.b   #$10,D6
    beq     .nextDir                                    ; skip subdirectories entries
    cmp.b   #$f,D6
    beq     .nextDir                                    ; skip long filename entries

    ; check to see if we have found the CPM Image file
    ; The name CPMDISK.IMG is stored as "CPMDISK " then "IMG" in FAT32
    LEA     imageName,A4
    cmp.l   (A4)+,(A5)+
    bne     .nextDir
    cmp.l   (A4)+,(A5)+
    bne     .nextDir
    move.l  (A5),D6                                      ; wipe last byte from FAT to compare to 0 from imageName
    clr.b   D6
    cmp.l   (A4),D6
    bne     .nextDir

    ; found file, A5 will now be pointing at entry[8] so adjust offsets to compensate
    ;        block = entry[20,21] << 16 + entry[26,27]
    ; get starting block of CPMDISK.IMG
    move.w  $c(A5),D6 
    rol.w   #8,D6
    swap    D6
    move.w  $12(A5),D6
    rol.w   #8,D6

    ; for efficiency we will point blockCPMImage at the actual block on the sd card
    add.w  (rootDirectorySector),D6
    subq.l #2,D6                                        ; allows for the fact that the root directory is from sector 2 onwards in FAT32   
    move.l D6,blockCPMImage

    move.l  #TRAPHNDL,$8c                               ; set up trap #3 handler
    moveq.l #0,D0                                       ; log on disk A, user 0
    rts

.nextDir:
    addq.l  #1,D4                                       ; look at next directory entry
    jmp     .startDirectoryEntry

.errExit:
    moveq.l #1,D1                                       ; Func code is 1 PRINTLN, A0 preloaded with address of error message
    trap    #14                          
    moveq.l #1,D0                                       ; signal error
    rts

TRAPHNDL:
    cmpi    #23,D0                                      ; Function call in range ?
    bcc     TRAPNG

    lsl.l   #2,D0                                       ; change function call to offset by multiplting by 4
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
    jmp     _ccp

CONSTAT: 
; Check for keyboard input. Set d0 to 1 if keyboard input is pending, otherwise set to 0.
    moveq.l #7,D0                        ; use EASy68k trap 15 task 7
    trap    #15                          ; d1.b = 1 if keyboard ready, otherwise = 0
    moveq.l #0,D0
    move.b  D1,D0
    rts
         
CONIN:    
; Read single ASCII character from the keyboard into d0
; Rosco implementation of this trap waits for input
    moveq.l #5,D0                        ; use EASy68k trap 15 task 5
    trap    #15                          ; d1.b contains the ascii character
    move.b  D1,D0      
    and.l   #$7f,D0                      ; only use 7 bit character set
    rts

CONOUT: 
; Display single ASCII character in d1
    moveq.l #6,D0                        ; use EASy68k trap 15 task 6
    trap    #15
    rts                                  ; and exit

LSTOUT:    
PUN:
RDR:
GETIOB:
SETIOB:
    moveq.l #0,D0
    rts

LISTST:    
    move.b #$ff,D0
    rts

HOME:    
    clr.w  TRACK
    rts

SELDSK:    
; drive should be in d1.b
    cmp.b   #1,D1
    beq     .seldrive1     
    move.b  #0,SELDRV
    move.l  #DPH0,D0
    rts

.seldrive1
    move.b  #1,SELDRV
    move.l  #DPH1,D0
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
; Read one cpm sector from requested disk, track, sector to dma address
; Can be a cpmimage on the sd card or the ram disk
    cmp.b   #0,SELDRV
    bne     .readRAMDrive

    bsr     setupReadDisk                               ; sets A0 to point to the right 128 bytes in memory, potentially reading from disk
    move.l  DMA,A1
    copyData
    moveq.l #0,D0                                       ; return OK status         
    rts

.readRAMDrive:
    bsr     setupReadRAM                                ; sets A0 to point to the right 128 bytes in memory to read
    debugPrintRAM 'R'
    move.l  DMA,A1
    copyData
    moveq.l #0,D0                                       ; return OK status         
    rts         

setupReadRAM:
; translate track/sector into RAM location on the RAM drive
    moveq.l #0,D0
    move.w  TRACK,D0
    moveq.l #12,D3                                      ; much faster than shifting by 8 then 4 (40 versus 12 cycles)
    lsl.l   D3,D0

    moveq.l #0,D2
    move.w  SECTOR,D2
    moveq.l #7,D3                                       ; much faster than shifting by 7 (22 versus 12 cycles)
    lsl.l   D3,D2

    add.l   D2,D0
    add.l   #ramDriveLocation,D0                        ; add base address of RAM drive
    movea.l D0,A0                                       ; point to the track/sector in RAM drive
    rts

setupReadDisk:
;
; algorithm
;
; keep 512b in a memory buffer
; keep sector number of the data currently in the buffer
;
; if requested sector not in buffer {
;     calcuate the sector and offset that the FAT entry for the sector is located in
;     read sector pointed to in FAT table from disk into buffer
;     note requested sector in buffer
; }
;
; calculate offset of CPM 128b required in 512b buffer
; copy the correct 12b across into the CPM dma area

    ; start by calculating the requested (FAT32) sector number from TRACK and SECTOR in D0
    ; also calculate the offset into that 512b buffer for the 128b CPM sector data in D3
    moveq.l #0,D1
    move.w  TRACK,D1
    lsl.l   #3,D1

    moveq.l #0,D2
    move.w  SECTOR,D2

    move.l  D2,D3
    and.l   #3,D3                                       ; use D3 to calculate the offset of the 128b CPM sector in the 512b FAT sector
    moveq.l #7,D4                                       ; much faster than shifting by 7 (22 versus 12 cycles)
    lsl.l   D4,D3

    lsr.l   #2,D2
    add.l   D2,D1                                        ; D1 now has the requested sector number
    add.l   (blockCPMImage),D1                           ; D1 now has the actual sector on the SD card

    ; check to see if this FAT32 sector already in memory
    cmp.l (lastFATSector),D1
    beq   .noDiskReadRequired

    ; we are going to read the sector (hopefully) so update the last read FAT sector before we lose the contents of D1
    move.l D1,lastFATSector

    ; we assume that the FAT table is contiguous for the CP/M image
    ; file, this avoids a walk of the FAT table linked list .. but wont deal with any bad sectors on the sd card

    lea     sd,A1
    moveq.l #2,D0                                        ; read sector function code
    lea     sdBuf,A2
    trap    #13
    cmp.l   #0,D0                                        ; check return
    bne     .noDiskReadError

    ; if we get here we had a disk read error
    debugPrintSector 'E'
    
    lea     msgNoSdCardRead,A0
    moveq.l #1,D1                                       ; Func code is 1 PRINTLN, A0 preloaded with address of error message
    trap    #14                         
    moveq.l #1,D0                                       ; signal error

    move.l  #-1,lastFATSector

    lea     sdBuf,A0
    move.l  DMA,A1
    move.b  #$ff,D2
    rts                                                 ; Mmm .. doesn't flag an error, BIOS will continue 

.noDiskReadError:
    debugPrintSector 'R'
    ;jmp    .noCachePrint

.noDiskReadRequired:
    ;debugPrintSector 'C'
    
.noCachePrint:
    lea    sdBuf,A0
    add.l  D3,A0                                        ; add offset into 512b buffer
    rts

WRITE:
; Write one cpm sector from requested disk, track, sector to dma address
; Can be a cpmimage on the sd card or the ram disk
    cmp.b   #0,SELDRV
    bne     .writeRAMDrive

    ; going to write to disk
    bsr     setupReadDisk                               ; sets A0 to point to the right 128 bytes in memory, potentially reading from disk
    debugPrintSector 'W'
    move.l  DMA,A1
    exg     A0,A1
    copyData

    ; and write out the 512b buffer to disk
    move.l  (lastFATSector),D1                          ; set up in SETUPRD
    lea     sd,A1
    moveq.l #3,D0                                       ; write sector function call
    lea     sdBuf,A2
    trap    #13
    cmp.l   #0,D0                                       ; check return
    bne     .noWriteError
    lea     msgNoSdCardWrite,A0
    moveq.l #1,D1                                       ; Func code is 1 PRINTLN, A0 preloaded with address of error message
    trap    #14                                         ; TRAP to firmware    
    moveq.l #1,D0                                       ; signal error
    rts
    
.noWriteError:
    ;move.l #-1,lastFATSector
    moveq.l #0,D0                                       ; return success
    rts                    

.writeRAMDrive:
    bsr     setupReadRAM                                ; sets A0 to point to the right 128 bytes in memory to read
    debugPrintRAM 'W'
    move.l  DMA,A1
    exg     A0,A1
    copyData
    moveq.l #0,D0
    rts        

FLUSH:
    moveq.l #0,D0                                       ; return successful
    rts

GETSEG:
    move.l #MEMRGN,D0                                   ; return address of mem region table
    rts

SETEXC:
    andi.l  #$ff,D1                                     ; do only for exceptions 0 - 255

    cmpi    #45,D1
    beq     NOSET                                       ; don't set trap 13,14,15 as used by rosco firmware
    cmpi    #46,D1
    beq     NOSET                        
    cmpi    #47,D1
    beq     NOSET                       
    cmpi    #9,D1                                       ; don't set trace trap
    beq     NOSET
    lsl     #2,D1                                       ; multiply exception number by 4
    movea.l D1,A0
    move.l  (A0),D0                                     ; return old vector value
    move.l  D2,(A0)                                     ; insert new vector

NOSET:    
    rts

* ************************************************************************** *
; Data
* ************************************************************************** *

              align 2                    ; DMA must be at even address
SELDRV        dc.b        $ff            ; drive requested by seldsk
RESV          dc.b        0              ; reserve byte, padding
TRACK         dc.w        0              ; track requested by settrk
SECTOR        dc.w        0              ; max sector value is 0x3FF
DMA           dc.l        0
SELCODE       dc.b        0              ; reserve byte
RESV1         dc.b        0              ; reserve byte, padding

; memory table must start on an even address
              align 2
MEMRGN        dc.w        1              ; 1 memory region
              dc.l        $20000         ; after the CP/M 
			  dc.l        $A0000         ; 524K bytes, more than enough for bootstrapping  

; disk parameter header - 4mb disk on sd card
DPH0:    
    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV0                       ; ptr to allocation vector

DPB0:    
    dc.w     32                          ; 32 sectors per track
    dc.b     4                           ; block shift for BLS of 2048
    dc.b     15                          ; block mask for BLS of 2048
    dc.b     0                           ; extent mask, EXM
    dc.b     0                           ; dummy fill
    dc.w     2047                        ; DSM, (1024 tracks * 32 sectors * 128 bytes /2048)-1
                           
    dc.w     255                         ; DRM, 256 directory entries
    dc.w     0                           ; directory mask
    dc.w     0                           ; permanent mounted drive, check size is zero
    dc.w     0                           ; no track offset


; disk parameter header - 128k ram disk 
DPH1:    
    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB1                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV1                       ; ptr to allocation vector

DPB1:    
    dc.w     32                          ; 32 sectors per track
    dc.b     4                           ; block shift for BLS of 2048
    dc.b     15                          ; block mask for BLS of 2048
    dc.b     0                           ; extent mask, EXM
    dc.b     0                           ; dummy fill
    dc.w     63                          ; DSM, (32 tracks * 32 sectors * 128 bytes /2048)-1
                           
    dc.w     255                         ; DRM, 256 directory entries
    dc.w     0                           ; directory mask
    dc.w     0                           ; permanent mounted drive, check size is zero
    dc.w     0                           ; no track offset


    align 2
DIRBUF:    
    ds.b     128                         ; directory buffer

ALV0:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV1:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

sdBuf:    
	ds.b     512                         ; buffer to read/write sectors to sd card

sd:
    ds.b     64                          ; needs to be large enough to hold a sd card structure

rootDirectorySector:                     ; sector where root directory starts on sd card
    dc.w     0

startFAT:                                ; sector where FAT table starts on sd card
    dc.w     0

blockCPMImage:                           ; block number of CPM image
    dc.l     0

lastFATSector:                           ; last FAT sector read (contents should be in sdBuf)
    dc.l     -1

imageName:
    dc.b     "CPMDISK IMG",0             ; Nameof CPM image file on SD card

msgNoSdCardSupport:
    dc.b     "error: No SD card support detected",0

msgNoSdCardInit:
    dc.b     "error: Unable to initialize SD card",0

msgNoSdCardRead:
    dc.b     "error: Unable to read SD card",0

msgNoSdCardWrite:
    dc.b     "error: Unable to write SD card",0

msgNoCPMImage:
    dc.b     "error: Cannot find CPMDISK.IMG in root directory of SD card",0
