;============================================================================
; MODULE: core/memory.asm
; DESC:   Memory utility primitives — zero, copy, compare
;
; All functions operate on DS segment (flat .COM model).
; All preserve registers unless documented otherwise.
;============================================================================

;---------------------------------------------------------------------------
; mem_zero — Fill a memory region with zero bytes
; IN:  DI = destination address
;      CX = byte count
; Clobbers: DI, CX (DI points past end on return)
;---------------------------------------------------------------------------
mem_zero:
    push    ax
    xor     al, al
    cld                                 ; ensure forward direction
    rep     stosb
    pop     ax
    ret

;---------------------------------------------------------------------------
; mem_fill — Fill a memory region with a byte value
; IN:  DI = destination address
;      AL = fill byte
;      CX = byte count
; Clobbers: DI, CX
;---------------------------------------------------------------------------
mem_fill:
    cld
    rep     stosb
    ret

;---------------------------------------------------------------------------
; mem_copy — Copy memory forward (non-overlapping or src < dst)
; IN:  SI = source address
;      DI = destination address
;      CX = byte count
; Clobbers: SI, DI, CX
;---------------------------------------------------------------------------
mem_copy:
    push    ax
    cld
    rep     movsb
    pop     ax
    ret

;---------------------------------------------------------------------------
; mem_copy_bwd — Copy memory backward (for overlapping src > dst)
; IN:  SI = source address (points at last byte)
;      DI = destination address (points at last byte)
;      CX = byte count
; Clobbers: SI, DI, CX
;---------------------------------------------------------------------------
mem_copy_bwd:
    push    ax
    std                                 ; backward direction
    rep     movsb
    cld                                 ; restore DF=0 (critical!)
    pop     ax
    ret

;---------------------------------------------------------------------------
; mem_compare — Compare two memory regions byte by byte
; IN:  SI = address A
;      DI = address B
;      CX = byte count
; OUT: ZF=1 if equal, ZF=0 if different
;      AL = 0 if equal, else the first differing byte from A
; Clobbers: SI, DI, CX, AX
;---------------------------------------------------------------------------
mem_compare:
    cld
.repe:
    cmpsb
    jne     .diff
    loop    .repe
    xor     al, al                      ; equal
    ret
.diff:
    mov     al, [si - 1]                ; first differing byte from A
    ret
