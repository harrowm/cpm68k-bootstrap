; Very simple cpm68k bios
; Malcolm Harrow August 2023

_ccp     equ $150BC                     ; hard location for _ccp of CPM15000.SR

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
    move.l  #0,D0                                       ; check sd card support
    trap    #13
    cmp.l   #$1234FEDC,D0                               ; check magic return
    beq     .noerr1
    lea     msgNoSdCardSupport,A0
    jmp     .errExit
    
.noerr1:
    ; init the sd card and get sd card structure back
    lea     sd,A1
    move.l  #1,D0                                       
    trap    #13
    cmp.l   #0,D0                                       ; check return
    beq     .noerr2
    lea     msgNoSdCardInit,A0
    jmp     .errExit

.noerr2:
    ; read the MBR from sector 0 so we can calculate position of the MBR and root diectory in the CPM image
    lea     sd,A1
    move.l  #2,D0                                       ; read the MBR from the sd card 
    move.l  #0,D1                                       ; sector number to read
    lea     sdBuf,A2
    trap    #13
    cmp.l   #0,D0                                       ; check return
    bne     .noerr3
    lea     msgNoSdCardRead,A0
    jmp     .errExit

.noerr3:
    move.w  $e+sdBuf,D6                                 ; number of reserved sectors from MBR.  Reversed due to endianess of 68000
    rol.w   #8,D6
    move.w  D6,startFAT

    move.l  $24+sdBuf,D6
    rol.w   #8,D6
    swap    D6
    rol.w   #8,D6
    move.w  D6,rootDirectorySector
    
    clr.w   D6                                          ; multiply by number of FAT tables
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
;      if directory_entry[0] == 0xE5 { // previously erased entry
;        continue
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
;        filelength = entry[28,29,30,31]
;        // both of these are store lsb first eg length of 0x7e84 is stored 84 7e 00 00
;        return success
;      }
;      entry++
;    }


    ; search the FAT to try to find the CPM disk image
    move.l  #0,D3                                       ; sector to read
    move.l  #0,D4                                       ; directory entry in sector.  Sector is 512b, directory table is 32b so 16 directories per sector

.startDirectoryEntry:
    move.l  D4,D5
    and.l   #15,D5                                      ; only look at last 4 bits, we want to calculate (directory entry % 16)
    bne     .noread                                     ; we dont need to read a new sector from the sd card

    ; read the MBR from sector 0 so we can calculate position of the MBR and root diectory in the CPM image
    lea     sd,A1
    move.l  #2,D0                                       ; read sector trap
    move.w  rootDirectorySector,D1
    add.w   D3,D1                                       ; sector number to read plus offset to rootDirectorySector
    lea     sdBuf,A2
    trap    #13
    cmp.l   #0,D0                                       ; check return
    bne     .noerr4
    lea     msgNoSdCardRead,A0
    jmp     .errExit

.noerr4:
    addq.l  #1,D3                                       ; increment next sector to read
    clr.l   D4                                          ; reset directory entry to zero 

.noread:
    move.l  D4,D5                                       ; D4 contains directory record
    lsl.l   #5,D5                                       ; multiply offset by 32 to get to start of directory record
    add.l   #sdBuf,D5
    move.l  D5,A5
    move.b  (A5),D6
    tst.b   D6                                          ; reached end of root directory entries
    bne     .continue1
    lea     msgNoCPMImage,A0
    jmp     .errExit

.continue1:
    move.b  $b(A5),D6
    cmp.b   #$10,D6
    beq     .nextDir                                    ; skip subdirectories entries
    cmp.b   #$f,D6
    beq     .nextDir                                    ; skip long filename entries

    ; an interesting string compare function!  looking for filename CPMDISK.IMG
    cmp.l   #$43504D44,(A5)+                            ; 'CPMD' = 0x43504D44
    bne     .nextDir
    cmp.l   #$49534B20,(A5)+                            ; 'ISK ' = 0x49534B20
    bne     .nextDir
    move.l  (A5),D6
    ori.l   #$ff,D6
    cmp.l   #$494D47FF,D6                               ; 'IMG*' = 0x494D47FF
    bne     .nextDir
    jmp     .foundCPMImage
    
.nextDir:
    addq.l  #1,D4                                       ; look at next directory entry
    jmp     .startDirectoryEntry

.foundCPMImage:
    ; found file, A5 will now be pointing at the third word in the directory entry "IMG*"
    ; i.e entry[8] so adjust offsets to compensate
    ;        block = entry[20,21] << 16 + entry[26,27]
    ; get starting block of CPMDISK.IMG
    move.w  $c(A5),D6
    rol.w   #8,D6
    swap    D6
    move.w  $12(A5),D6
    rol.w   #8,D6
    move.l  D6,blockCPMImage
    ;        filelength = entry[28,29,30,31]
    ; get file length of CPMDISK.IMG
    ; 
    ; moving the address as move.l causes an exception - alignment issue ?
    move.w  $16(A5),D6
    rol.w   #8,D6
    swap    D6
    move.w  $14(A5),D6
    rol.w   #8,D6
    move.l  D6,filelenCPMImage

    ;   
    move.l  #TRAPHNDL,$8c               ; set up trap #3 handler
    clr.l   D0                          ; log on disk A, user 0
    rts

.errExit:
    move.l  #1,D1                       ; Func code is 1 PRINTLN, A0 preloaded with address of error message
    trap    #14                         ; TRAP to firmware
    move.l  #1,D0                       ; signal error
    rts

TRAPHNDL:
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
    move.l #7,D0                        ; use EASy68k trap 15 task 7
    trap   #15                          ; d1.b = 1 if keyboard ready, otherwise = 0
    clr.l  D0
    move.b D1,D0
    rts
         
CONIN:    
; Read single ASCII character from the keyboard into d0
; Rosco implementation of this trap waits for input
    move.l #5,D0                        ; use EASy68k trap 15 task 5
    trap   #15                          ; d1.b contains the ascii character
    move.b D1,D0      
    and.l  #$7f,D0                      ; only use 7 bit character set
    rts

CONOUT: 
; Display single ASCII character in d1
    move.l #6,D0                        ; use EASy68k trap 15 task 6
    trap   #15
    rts                                 ; and exit

LSTOUT:    
PUN:
RDR:
GETIOB:
SETIOB:
    clr.l  D0                            ; HACK ?
    rts

LISTST:    
    move.b #$ff,D0
    rts

HOME:    
    clr.w  TRACK
    rts

SELDSK:    
; always assume one drive
    move.b  #0,SELDRV
    move.l  #DPH0,D0
    rts

SETTRK:    
    move.w  D1,TRACK


    ;clr.l   D1
    ;move.w  TRACK,D1
    ;add.l   #97,D1
    ;clr.l   D0
    ;jsr     CONOUT

    rts

SETSEC:    
    move.w  D1,SECTOR

    ;clr.l   D1
    ;move.w  SECTOR,D1
    ;add.l   #97,D1
    ;clr.l   D0
    ;jsr     CONOUT

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
; One small drive possible as loaded at 0x2000 and CPM starts at 0x15000
; This gives a max ram disk size of ~77k

    bsr     SETUPRD                      ; translate track/sector values into RAM loc
RAMDRVR:
    move.l (A0)+,(A1)+
    dbra   D2,RAMDRVR

    clr.l  D0                            ; return OK status         
    rts         

SETUPRD:
; replace the ram disk code below with code to read from the 4mb CPM disk image
;
; algorithm
;
; keep 512b in a memory buffer
; keep requested sector number of the sector currently in the buffer
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
    clr.l  D0
    move.w TRACK,D0
    lsl.l  #3,D0

    clr.l  D2
    move.w SECTOR,D2

    move.l D2,D3
    and.l  #3,D3                         ; use D3 to calculate the offset of the 128b cpm sector in the 512b FAT sector
    lsl.l  #7,D3

    lsr.l  #2,D2
    add.l  D2,D0                         ; D0 now has the requested sector number

    ; check to see if this FAT32 sector already in memory
    cmp.l (lastFATSector),D0
    beq   .nofatRead

    ; we are going to read the sector (hopefully) so update the last read FAT sector before we lose the contents of D0
    move.l D0,lastFATSector


    ;  as the next part of the bootstrap process, assume that th eFAT table is contiguous for the CP/M image
    ;  file, this avoids a walk of the FAT table linked list .. but wont deal with any bad sectors on the sd card

    move.l (blockCPMImage),D1
    add.l  D0,D1

    ;move.l D1,D5                                        ; offset of block number in FAT entry
    ;and.l  #$FF,D5
         
    add.w  (rootDirectorySector),D1                                ; this now has the sector containinbg the FAT entry for the requested sector
    sub.l  #2,D1 ; HACK !!

    ; calculate the right sector to read using the FAT table
    ;     startFAT contains the sector where the FAT table starts on the sd card
    ;     blockCPMImage contains the block within the FAT where the CPM image starts
    ; the FAT table is a table of sector ids, each 4b long, a sector is 512b so each sector contains 128 entries
    ; 

    ; first calculate the FAT table sector
    ; each sector is 512b, each fat entry is 4b, so 128 entries per sector
    ;move.l (blockCPMImage),D1
    ;add.l  D0,D1

    ;move.l D1,D5                                        ; offset of block number in FAT entry
    ;and.l  #$FF,D5

    ;lsr.l  #7,D1             
    ;add.w  (startFAT),D1                                ; this now has the sector containinbg the FAT entry for the requested sector
    
    ; read the FAT sector and get the real sector to read
    ;lea     sd,A1
    ;move.l  #2,D0                                       ; read sector trap
    ;lea     sdBuf,A2
    ;trap    #13
    ;cmp.l   #0,D0                                       ; check return
    ;bne     .noerr5
    ;lea     msgNoSdCardRead,A0
    ;move.l  A0,A1                                       ; tidy up return values
    ;move.b  #$ff,D2
    ;rts                                                 ; Mmm .. doesn't flag an error, BIOS will continue 

.noerr5:
    ; read the actual sector pointed to in the FAT table
    ;lea     sdBuf,A5
    ;lsl.l   #2,D5                                       ; convert offset to 4b long word addresses
    ;add.l   D5,A5
    ;move.l  (A5),D1                                     ; D1 now contains the actual sector to read, but need to switch endian
    ;rol.w   #8,D1
    ;swap    D1
    ;rol.w   #8,D1
    ;sub.l   #4,D1 ; HACK !!  directory entry starts at block 802, first file starts at block 803 with offset of 3 .. need to understand more
    ;add.w   (rootDirectorySector),D1                    ; now have actual sector on disk *HACK* should check that this is beyond the bounds of the CP/M image !

    lea     sd,A1
    move.l  #2,D0                                       ; read sector trap
    lea     sdBuf,A2
    trap    #13
    cmp.l   #0,D0                                       ; check return
    bne     .nofatRead
    lea     msgNoSdCardRead,A0
    move.l  A0,A1
    move.b  #$ff,D2
    rts                                                 ; Mmm .. doesn't flag an error, BIOS will continue 

.nofatRead:
    lea    sdBuf,A0
    add.l  D3,A0                                        ; add offset into 512b buffer
    move.l DMA,A1                                       ; get dma
    move.w #(128/4)-1,D2                                ; long word move 128 bytes of sector data
    rts




;
; translate track/sector into RAM location on the RAM drive

    ;clr.l   D1
    ;move.w  TRACK,D1
    ;add.l   #65,D1
    ;clr.l   D0
    ;jsr     CONOUT

    ;clr.l   D1
    ;move.w  SECTOR,D1
    ;add.l   #65,D1
    ;clr.l   D0
    ;jsr     CONOUT


    clr.l  D0
    move.w TRACK,D0
    lsl.l  #8,D0
    lsl.l  #4,D0
    clr.l  D2
    move.w SECTOR,D2
    lsl.l  #7,D2
    add.l  D2,D0
    add.l  #$C0000,D0                    ; add base address of RAM drive
    move.l D0,A0                         ; point to the track/sector in RAM drive
    move.l DMA,A1                        ; get dma
    move.w #(128/4)-1,D2                 ; long word move 128 bytes of sector data
    rts

WRITE:
; Write one sector to requested disk, track, sector from dma address
; Both drive A & B are RAM drive
    ;cmp.b  #2,SELDRV                     ; only drive C can be written
    ;bne    WRBAD
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

SETEXC:
    andi.l  #$ff,D1                      ; do only for exceptions 0 - 255

    cmpi    #45,D1
    beq     NOSET                        ; don't set trap 13,14,15 as used by rosco firmware
    cmpi    #46,D1
    beq     NOSET                        
    cmpi    #47,D1
    beq     NOSET                       

    cmpi    #9,D1                        ; don't set trace trap
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

              align 2                    ; DMA must be at even address
SELDRV        dc.b        $ff            ; drive requested by seldsk
RESV          dc.b        0              ; reserve byte, padding
CURCFSECT     dc.l        -1             ; current CF sector, the 512 bytes data of curtrk is in sectCF
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

; disk parameter header
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
    dc.w     2047                        ; DSM, (3 tracks * 1024 sectors * 128 bytes /2048)-1
                           
    dc.w     255                         ; DRM, 256 directory entries
    dc.w     0                           ; directory mask
    dc.w     0                           ; permanent mounted drive, check size is zero
    dc.w     0                           ; no track offset

;diskdef 4mb-hd-0
;  seclen 128
;  tracks 1024
;  sectrk 32
;  blocksize 2048
;  maxdir 256
;  skew 1
;  boottrk 0
;  os 2.2
;end
    align 2
DIRBUF:    
    ds.b     128                         ; directory buffer

ALV0:    
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

filelenCPMImage:                         ; file length of CPM image
    dc.l     0

lastFATSector:                           ; last FAT sector read (contents should be in sdBuf)
    dc.l     -1

msgNoSdCardSupport:
    dc.b     "error: No SD card support detected",0

msgNoSdCardInit:
    dc.b     "error: Unable to initialize SD card",0

msgNoSdCardRead:
    dc.b     "error: Unable to read SD card",0

msgNoCPMImage:
    dc.b     "error: Cannot find CPMDISK.IMG in root directory of SD card",0

strPath:
    dc.b     "disk1.img",0               ; needs to be a path not a filename (leading /)

strCPMImage:                             ; name of CPM drive image (note space), null terminated
    dc.b     "CPMDISK IMG",0