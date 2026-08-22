; Retro-Amiga compliance demo -- a boot-block program.
;
; WRITTEN, NOT SOURCED. The demo has to be a file the user opens from their
; own library, and every Amiga program that could serve that purpose is
; somebody's. This one is ours.
;
; WHY A BOOT BLOCK. It talks to the chipset directly -- copper, DMA, colour
; registers -- and calls nothing in the ROM beyond AllocMem. So it does not
; care whose Kickstart is fitted: it is the same demo on the bundled AROS
; ROM and on a real Kickstart, which is exactly the claim the compliance
; page makes.
;
; It draws a moving field of colour bars and then loops. There is no text:
; a boot block has no font, and drawing one would be more code than the
; thing it is demonstrating.

EXECBASE    equ 4
AllocMem    equ -198
CUSTOM      equ $dff000
DMACON      equ $096
COP1LC      equ $080
COPJMP1     equ $088
BPLCON0     equ $100
COLOR00     equ $180

BARS        equ 48              ; colour bars down the screen
CLSIZE      equ (BARS*8)+16     ; wait+move per bar, plus the end marker

            section code,code

            dc.b    'D','O','S',0
            dc.l    0                   ; checksum, filled in by the builder
            dc.l    880                 ; root block

start:      movem.l d0-d7/a0-a6,-(sp)
            move.l  EXECBASE.w,a6

            ; Chip RAM for the copper list. The block itself may have been
            ; loaded anywhere, and the copper can only read chip.
            move.l  #CLSIZE,d0
            move.l  #$10002,d1          ; MEMF_CHIP | MEMF_CLEAR
            jsr     AllocMem(a6)
            tst.l   d0
            beq     .done
            move.l  d0,a3
            move.l  d0,a2               ; write pointer

            ; One WAIT + one COLOR00 per bar, stepping four lines at a time
            ; from the top of the visible display.
            move.w  #$2c07,d2           ; first wait position: line $2c
            move.w  #BARS-1,d3
            moveq   #1,d4               ; colour, walked upwards
.bar:       move.w  d2,(a2)+
            move.w  #$fffe,(a2)+
            move.w  #COLOR00,(a2)+
            move.w  d4,(a2)+
            add.w   #$0400,d2           ; four scanlines on
            add.w   #$0123,d4           ; a different colour each bar
            dbf     d3,.bar

            move.l  #$fffffffe,(a2)+    ; end of copper list

            lea     CUSTOM,a5
            move.w  #$0000,BPLCON0(a5)  ; no bitplanes: the background shows
            move.w  #$7fff,DMACON(a5)   ; everything off first
            move.l  a3,COP1LC(a5)
            move.w  d0,COPJMP1(a5)      ; strobe: start the list now
            move.w  #$8280,DMACON(a5)   ; DMAEN | COPEN

.spin:      bra.s   .spin               ; the demo IS the display

.done:      movem.l (sp)+,d0-d7/a0-a6
            moveq   #0,d0
            rts

            end
