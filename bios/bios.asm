; Very simple cpm68k bios
; Malcolm Harrow August 2023 to June 2024
; Yes, it wasn't that simple ..

_ccp               equ $150BC                           ; hard location for _ccp of CPM15000.SR
ramDriveLocation   equ $C0000                           ; memory location for RAM drive
DEBUG              set 0                                ; set to 1 to print debug messgae, 0 turns off  

; print sector information read from / written to a SD disk image (or real SD card)
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

; print sector information read from / written to a RAM disk
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
        move.b  #'-',D1                                     
        trap    #15

        moveq.l #15,D0
        move.l  (DMA),D1                          ; sector in hex
        move.b  #16,D2
        trap    #15

        moveq.l #6,D0
        move.b  #' ',D1                                     
        trap    #15

        movem.l (A7)+,D0-D3/A0-A3
    ENDIF
ENDM

; print the number at address \1 in hex
debugPrintNum MACRO
        movem.l D0-D3/A0-A3,-(A7)
        moveq.l #15,D0
        move.l  (\1),D1
        move.b  #16,D2
        trap    #15
        movem.l (A7)+,D0-D3/A0-A3
ENDM

; Macros to call traps and save any registers that are changed

; print a string using trap 14,1 whilst preseving register A0
PrintStr MACRO
    movem.l D0-D3/A0-A3,-(A7)
    lea     \1,A0
    moveq.l #1,D1                                       
    trap    #14  
    movem.l (A7)+,D0-D3/A0-A3
ENDM


_init::    
    ; at this stage, we have loaded from the SDCARD, so we know its valid, no need to re-init
    ; need to find the starting sector of the CPM disk image on the sd card.
    ; To do this we will trawl through the FAT32 boot record etc

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
    movem.l D0-D3/A0-A3,-(A7)
    moveq.l #0,D0
    trap    #13
    cmp.l   #$1234FEDC,D0                               ; check magic return
    bne     .errNoSDsupport
    movem.l (A7)+,D0-D3/A0-A3

    ; init the sd card and get sd card structure back
    movem.l D0-D3/A0-A3,-(A7)
    lea     sd,A1
    moveq.l #1,D0                                       
    trap    #13
    cmp.l   #0,D0                                       ; check return
    bne     .errNoSDinit
    movem.l (A7)+,D0-D3/A0-A3

    ; read the MBR from sector 0 on the disk so we can read the partition table
    movem.l D0-D3/A0-A3,-(A7)
    lea     sd,A1
    moveq.l #2,D0                                       ; read the MBR from the sd card 
    moveq.l #0,D1                                       ; sector number to read
    lea     sdBuf,A2
    trap    #13
    cmp.l   #0,D0                                       ; check return
    beq     .errNoReadDiskMBR
    movem.l (A7)+,D0-D3/A0-A3

    ; now we need to check the disk MBR for a partition table and get the offset to the first partition
    ; this is a bodge .. CPM has to be on the first partition, partiton 0 and 0x1BE on the disk MBR
    ; The code should really check all 4 partitions ..

    ; as we read longs and words off of the MBR we have to take endianess into account and switch the byte order 
    ; as we are on the 68000 CPU
    move.l  $1c6+sdBuf,D6                               ; read LBA start from partition 0
    rol.w   #8,D6
    swap    D6
    rol.w   #8,D6
    move.l  D6,partStartSector

    ; read the MBR from sector 0 of the partition so we can calculate position of the root diectory and hence the CPM image
    movem.l D0-D3/A0-A3,-(A7)
    lea     sd,A1
    moveq.l #2,D0                                       ; read the MBR from the sd card 
    move.l  D6,D1                                       ; sector number to read - partStartSector
    lea     sdBuf,A2
    trap    #13
    cmp.l   #0,D0                                       ; check return
    beq     .errNoReadPartMBR
    movem.l (A7)+,D0-D3/A0-A3

    move.w  $e+sdBuf,D6                                 ; number of reserved sectors from MBR.  Reversed due to endianess of 68000
    rol.w   #8,D6
    move.w  D6,reservedSectors

    move.l  $2c+sdBuf,D6                                ; read root director cluster (usually 2)
    rol.w   #8,D6
    swap    D6
    rol.w   #8,D6
    move.l  D6,rootDirectoryCluster

    ; up until the root directory, we use sectors; after the root directory we have to deal with clusters (groups of sectors)
    ; see the diagram here: https://eric-lo.gitbook.io/lab9-filesystem/overview-of-fat32#
    ; we need to store the number of sectors per cluster for later use
    moveq.l #0,D6
    move.b  $d+sdBuf,D6                                 ; read number of sectors per cluster
    move.w  D6,sectorsPerCluster                        ; save as a word for later mulu

    ; Calculate the sector of the root directory: 
    ; = sectors per FAT * number of FATs + number of reserved sectors
    ; += partStartSector to allow for the start of the partition on the disk
    move.l  $24+sdBuf,D5                                ; read sectors per FAT
    rol.w   #8,D5
    swap    D5
    rol.w   #8,D5
    
    moveq.l #0,D6                                       ; read number of FAT tables
    move.b  $10+sdBuf,D6

    mulu.w  D5,D6
    add.w   reservedSectors,D6
    add.l   partStartSector,D6                          ; partStartSector is a long
    move.w  D6,rootDirectorySector


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
    movem.l D0-D3/A0-A3,-(A7)
    lea     sd,A1
    moveq.l #2,D0                                       ; read sector trap
    moveq.l #0,D1                                       ; required for r68k to work correctly
    move.w  rootDirectorySector,D1
    add.w   D3,D1                                       ; sector number to read plus offset to rootDirectoryCluster
    lea     sdBuf,A2
    trap    #13
    cmp.l   #0,D0                                       ; check return
    cmp.l   #0,D0                                       ; check return
    beq     .errReadError
    movem.l (A7)+,D0-D3/A0-A3

    addq.l  #1,D3                                       ; increment next sector to read
    moveq.l #0,D4                                       ; reset directory entry to zero 

.noReadRequired:
    move.l  D4,D5                                       ; D4 contains directory record
    lsl.l   #5,D5                                       ; multiply offset by 32 to get to start of directory record
    add.l   #sdBuf,D5
    movea.l D5,A5
    move.b  (A5),D6
    tst.b   D6                                          ; reached end of root directory entries
    beq     .dirEnd

.notDirEnd:
    move.b  $b(A5),D6
    cmp.b   #$10,D6
    beq     .nextDir                                    ; skip subdirectories entries
    cmp.b   #$f,D6
    beq     .nextDir                                    ; skip long filename entries

    ; check to see if we have found the CPM Image file
    ; Check that name starts "CPMD"
    LEA     imageName,A4
    cmp.l   (A4)+,(A5)+
    bne     .nextDir

    ; Check that the name ends in "IMG*"    
    addq    #4,A4
    addq    #4,A5
    move.l  (A5),D6                                      ; wipe last byte from FAT to compare to 0 from imageName
    clr.b   D6
    cmp.l   (A4),D6
    bne     .nextDir

    ; Now look at the middle "ISK*"
    ; The * can be a space or A..P
    subq    #4,A4
    subq    #4,A5

    move.l  (A4),D5                                      ; save last characters
    move.l  (A5)+,D6                                     ; increment A5 so that its aligned for below                                      
    move.b  D6,D5                                        ; make last byte the same
    cmp.l   D5,D6                                        ; Check that "ISK" is the same
    bne     .nextDir

    and.l   #$FF,D6                                      ; clear top 3 bytes
    ; Now left to check last character
    cmp.b   #' ',D6                                      ; CMPDISK.IMG found
    beq     .foundCMPDISK

.checkdriveletter
    sub.b   #'A',D6
    bmi     .notvaliddrive
    cmp.b   #15,D6
    ble     .validdrive
 
.notvaliddrive
    ; MESSAGE IGNOREING
    PrintStr msgIgnoreMapDrive
    bne     .nextDir

.foundCMPDISK
    ; change D6 to 16 (one past end of CPMDRIVE table) and fall through
    move.b  #16,D6
   
.validdrive
    ; found file, A5 will now be pointing at entry[8] so adjust offsets to compensate
    ;        block = entry[20,21] << 16 + entry[26,27]
    ; get starting block of CPMDISK.IMG
    move.w  $c(A5),D5                                   
    rol.w   #8,D5
    swap    D5
    move.w  $12(A5),D5
    rol.w   #8,D5

    sub.l   (rootDirectoryCluster),D5                   ; allow for the position of the root directory (usually 2)
    mulu.w  (sectorsPerCluster),D5  

    ; for efficiency we will point CPMImageSector at the actual block on the sd card
    add.w   (rootDirectorySector),D5

    move.b  D6,D2                                       ; Save for printing drive later

    lea     CPMDISK,A0
    add.b   D6,D6
    add.b   D6,D6
    add.l   D6,A0
    move.l  D5,(A0)

    ; Print out a message about the mapping (if not CPMDISK.IMG, this printed later after other drives assigned)
    ; HACK sort this out msgMapDriveSource

    cmp.b   #16,D2                                      ; Skip over CPMDISK.IMG 
    beq     .nextDir

    move.b  #'A',D1                                      
    add.b   D2,D1
    move.b  D1,msgMapDriveLetter
    move.b  D1,msgMapDriveSource

    PrintStr msgMapDrive

.nextDir:
    addq.l  #1,D4                                       ; look at next directory entry
    bra     .startDirectoryEntry

    ; So now we have read the whole directory and need to do some tidy up:
    ;   if we have found "CPMDISK.IMG" then we need to place this in the table if possible 
    ;   we need to try to place the RAMDISK in the mapping table
    ; Why have CPMDISK.IMG ? TO me most people will only want one disk .. and this is the best name :o

.dirEnd
    lea     CPMDISK,A1
    move.l  (CPMDISK+64),D1                             ; "CPMDISK.IMG" sector if found stored at 17th entry in table
    moveq   #15,D3                                      ; looping variable, 16=max number of drives, -1 for dbra
.nextdiskmap
    tst.l   (A1)
    bne     .continue                                   ; not an empty slot, try to loop around

    tst.b   D1                                          ; see if we need to map CPMDISK.IMG
    beq     .sortoutramdrive
    move.l  D1,(A1)

    ; format drive letter for message
    move.b  #'A'+15,D1                                      
    sub.b   D3,D1
    move.b  D1,msgMapCPMDriveLetter

    PrintStr msgMapCPMDrive
    moveq   #0,D1                                       ; note that CPMDISK.IMG now mapped
    
.continue
    addq    #4,A1    
    dbra    D3,.nextdiskmap

    ; Need to check is we failed to map CPMDRIVE.IMG and RAMDRIVE and message
    bra     .finish

.sortoutramdrive
    moveq   #15,D1                                      ; reuse D1
    sub.b   D3,D1
    move.b  D1,RAMDRIVE                                 ; now that we fix up RAMDRIVE we are done, so can fall out of loop

    ; message RAM drive mapping
    add.b   #'A',D1
    move.b  D1,msgMapRAMDriveLetter
    PrintStr msgMapRAMDrive

.finish
    move.l  #TRAPHNDL,$8c                               ; set up trap #3 handler
    moveq.l #0,D0                                       ; log on disk A, user 0
    rts

; errors during _init 
.errNoSDsupport
    movem.l (A7)+,D0-D3/A0-A3
    PrintStr msgNoSdCardSupport
    moveq.l #1,D0                                       ; signal error
    rts

 .errNoSDinit:
    movem.l (A7)+,D0-D3/A0-A3
    PrintStr msgNoSdCardInit
    moveq.l #1,D0                                       ; signal error
    rts

.errNoReadDiskMBR:
    movem.l (A7)+,D0-D3/A0-A3
    PrintStr msgNoSdCardReadMBR
    moveq.l #1,D0                                       ; signal error
    rts

.errNoReadPartMBR:
    movem.l (A7)+,D0-D3/A0-A3
    PrintStr msgNoSdCardRead
    moveq.l #1,D0                                       ; signal error
    rts

.errReadError:    
    movem.l (A7)+,D0-D3/A0-A3
    PrintStr msgNoSdCardRead
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
    dc.l    MISSING
    dc.l    GETSEG
    dc.l    GETIOB
    dc.l    SETIOB
    dc.l    FLUSH
    dc.l    SETEXC


WBOOT:  
    jmp     _ccp

CONSTAT: 
; Check for keyboard input. Set d0 to 1 if keyboard input is pending, otherwise set to 0.
    movem.l D1,-(A7)
    moveq.l #7,D0                        ; use EASy68k trap 15 task 7
    trap    #15                          ; d1.b = 1 if keyboard ready, otherwise = 0
    moveq.l #0,D0

    cmp.b   #1,D1
    bne     .end_constat

    move.b  #$FF,D0                      ; return 0xFF if keyboard ready according to CPM68k manual
.end_constat:
    movem.l (A7)+,D1
    rts

CONIN:    
; Read single ASCII character from the keyboard into d0
; Rosco implementation of this trap waits for input, which is what we need for CPM68k
    movem.l D1-D7/A0-A6,-(A7)
    moveq.l #5,D0                        ; use EASy68k trap 15 task 5
    trap    #15                          ; d1.b contains the ascii character
    move.b  D1,D0      
    and.l   #$7f,D0                      ; only use 7 bit character set
    movem.l (A7)+,D1-D7/A0-A6
    rts

CONOUT: 
; Display single ASCII character in d1
    movem.l D0-D7/A0-A6,-(A7)
    moveq.l #6,D0                        ; use EASy68k trap 15 task 6
    trap    #15
    movem.l (A7)+,D0-D7/A0-A6
    rts                                  ; and exit

LSTOUT:    
    rts

PUN:
    move.w  D1,D0
    rts

RDR:
    move.w  #$1a,D0                      ; return end of file as per CPM68k manual
    rts

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
; now trashes A0

    ; as spotted by jjlov, D1 can come in dirty, so clean
    and.l   #15,D1

    cmp.b   (RAMDRIVE),D1
    beq     .selram

    moveq   #0,D0
    move.b  D1,D0                   ; save for later

    add.b   D1,D1                   ; Multiply D1 by 4 to change to address
    add.b   D1,D1
    lea     CPMDISK,A0
    move.l  (0,A0,D1.L),D1          ; move sector for the requested disk to D1
    
    beq     .seldsk_error           ; zero so no disk mapped to this slot

    move.l  D1,(CPMImageSector)     ; set up FAT32 sector for disk image for read/write routine
                                    
    move.b  D0,SELDRV               ; set up selected drive
    mulu    #26,D0                  ; 26 is the size of the DPH 
    lea     DPH0,A0
    add.l   A0,D0                   ; return D0 pointing to the right DPH
    rts

.selram
    move.b  D1,SELDRV
    move.l  #DPH1,D0
    rts
    
.seldsk_error
    moveq   #0,D0                   ; Signal error
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

MISSING:
    ; this number is missing from the table in the
    ; CPM 68k documentation, doesn't seem to be ever called
    rts

READ:
; Read one cpm sector from requested disk, track, sector to dma address
; Can be a cpmimage on the sd card or the ram disk
    move.b  (RAMDRIVE),D0
    cmp.b   SELDRV,D0
    beq     .readRAMDrive

    bsr     setupReadDisk                               ; sets A0 to point to the right 128 bytes in memory, potentially reading from disk
    move.l  DMA,A1
    move.l  #(128/4-1),D0  

.MOVE_LOOP1:
    MOVE.L  (A0)+,(A1)+                                 ; copy long word from source to dest
    dbra    D0,.MOVE_LOOP1
    
    moveq.l #0,D0                                       ; return OK status         
    rts

.readRAMDrive:
    bsr     setupReadRAM                                ; sets A0 to point to the right 128 bytes in memory to read
    debugPrintRAM 'R'
    move.l  DMA,A1
    move.l  #(128/4-1),d0  

.MOVE_LOOP2:
    MOVE.L  (A0)+,(A1)+                                 ; copy long word from source to dest
    dbra    D0,.MOVE_LOOP2

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
    
    ; this routine returns the address of the 128 byte sector in the 512 FAT sector memory buffer in A0
    movem.l D0-D4/A1-A3,-(A7)
    
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
    add.l   (CPMImageSector),D1                          ; D1 now has the actual sector on the SD card

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
    beq     .errDiskReadError

    debugPrintSector 'R'
    ;jmp    .noCachePrint

.noDiskReadRequired:
    ;debugPrintSector 'C'
    
.noCachePrint:
    lea    sdBuf,A0
    add.l  D3,A0                                        ; add offset into 512b buffer
    movem.l (A7)+,D0-D4/A1-A3
    rts

.errDiskReadError:
    ; if we get here we had a disk read error
    movem.l (A7)+,D0-D4/A1-A3

    debugPrintSector 'E'    
    PrintStr msgNoSdCardRead

    moveq.l #1,D0                                       ; signal error

    move.l  #-1,lastFATSector
    move.l  #$ff,D2
    chk     #1,D2                                       ; cause a trap to stop execution
    rts                                                 ; should not get here .. 

WRITE:
; Write one cpm sector from requested disk, track, sector to dma address
; Can be a cpmimage on the sd card or the ram disk
; We always write sectors immediately so no need to implement "write to directory sector"
    move.b  (RAMDRIVE),D0
    cmp.b   SELDRV,D0
    beq     .writeRAMDrive

    ; going to write to disk    
    bsr     setupReadDisk                               ; sets A0 to point to the right 128 bytes in memory, potentially reading from disk
    debugPrintSector 'W'
    move.l  DMA,A1
    move.l  #(128/4-1),d0  
    
.MOVE_LOOP3:
    MOVE.L  (A1)+,(A0)+                                 ; copy long word from source to dest, reverse direction from read
    dbra    D0,.MOVE_LOOP3

    ; and write out the 512b buffer to disk
    ; tyhisi sthe last function for the CPM BIOS call, so we dont need to preserve the registers when we call the trap
    move.l  (lastFATSector),D1                          ; set up in SETUPRD
    lea     sd,A1
    moveq.l #3,D0                                       ; write sector function call
    lea     sdBuf,A2                                    ; write out sdBuf to disk
    trap    #13
    cmp.l   #0,D0                                       ; check return
    beq     .errWriteError

    moveq.l #0,D0                                       ; return success
    rts                    

.errWriteError:
    PrintStr msgNoSdCardWrite
    moveq.l #1,D0                                       ; signal error
    rts
    
.writeRAMDrive:
    bsr     setupReadRAM                                ; sets A0 to point to the right 128 bytes in memory to read
    debugPrintRAM 'W'
    move.l  DMA,A1
    move.l  #(128/4-1),d0  

.MOVE_LOOP4:
    MOVE.L  (A1)+,(A0)+                                 ; copy long word from source to dest, reverse direction from read
    dbra    D0,.MOVE_LOOP4

    moveq.l #0,D0
    rts        

FLUSH:
    ; we always write each CPM sector immediatley, so no need to implement flush
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
    ;cmpi    #9,D1                                       ; don't set trace trap
    ;beq     NOSET
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
              dc.l        $20000         ; try 128k ...
;			  dc.l        $80000         ; length of 524K bytes, more than enough for bootstrapping  

; Drive mapping; 0xFFFFFFFF means mapped to Ram disk, 0 not present otherwise records
; the sector of the logical file on the FAT32 SD Card
; Max of 16 disks 
CPMDISK:
    ds.l      17,0                       ; 16 drives plus one slot for "CPMDISK.IMG" which gets mapped to one of the other 16
RAMDRIVE:
    dc.b      0                          ; mappimg for RAM disk
    dc.b      0                          ; padding

; disk parameter header - 4mb disk on sd card
; set this up for 16 disks .. DPB and DIRBUF can be reused, ALV cannot ..
DPH0:  
    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV0                       ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV1                       ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV2                       ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV3                       ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV4                       ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV5                       ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV6                       ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV7                       ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV8                       ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV9                       ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV10                      ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV11                      ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV12                      ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV13                      ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV14                      ; ptr to allocation vector

    dc.l      0                          ; no sector translation table
    dc.w      0                          ; dummy
    dc.w      0
    dc.w      0
    dc.l      DIRBUF                     ; ptr to directory buffer
    dc.l      DPB0                       ; ptr to disk parameter block
    dc.l      0                          ; permanent drive, no check vector
    dc.l      ALV15                      ; ptr to allocation vector


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
    dc.l      ALV16                      ; ptr to allocation vector

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

ALV2:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV3:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV4:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV5:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV6:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV7:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV8:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV9:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV10:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV11:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV12:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV13:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV14:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV15:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

ALV16:    
	ds.b     256                         ; allocation vector, DSM/8+1 = 128

sdBuf:    
	ds.b     512                         ; buffer to read/write sectors to sd card

sd:
    ds.b     64                          ; needs to be large enough to hold a sd card structure

partStartSector:                         ; starting sector for partition 0 on the disk
    dc.l     0

rootDirectoryCluster:                    ; cluster of root directory - usually 2
    dc.l     0

rootDirectorySector:                     ; sector where root directory starts on sd card
    dc.w     0

reservedSectors:                         ; sector where FAT table starts on sd card
    dc.w     0

sectorsPerCluster:                       ; sectors per cluster in word format
    dc.w     0

CPMImageSector:                          ; sector number of CPM image for the current disk
    dc.l     0

lastFATSector:                           ; last FAT sector read (contents should be in sdBuf)
    dc.l     -1

imageName:
    dc.b     "CPMDISK IMG",0             ; Nameof CPM image file on SD card

msgNoSdCardSupport:
    dc.b     "error: No SD card support detected",0

msgNoSdCardInit:
    dc.b     "error: Unable to initialize SD card",0

msgNoSdCardReadMBR:
    dc.b     "error: Unable to read SD card MBR",0

msgNoSdCardRead:
    dc.b     "error: Unable to read SD card",0

msgNoSdCardWrite:
    dc.b     "error: Unable to write SD card",0

msgNoCPMImage:
    dc.b     "error: Cannot find CPMDISK.IMG in root directory of partition 0 on SD card",0
msgMapCPMDrive:
    dc.b     "Mapped CPMDISK.IMG to "
msgMapCPMDriveLetter:
    dc.b     "Q:",0
msgMapRAMDrive:
    dc.b     "Mapped RAM drive to "
msgMapRAMDriveLetter:
    dc.b     "Q:",0
msgMapDrive:
    dc.b     "Mapped CPMDISK"
msgMapDriveSource:
    dc.b     "Q.IMG to "
msgMapDriveLetter:
    dc.b     "Q:",0
msgIgnoreMapDrive:
    dc.b     "Ignoring CPMDISK file with drive letter after P",0