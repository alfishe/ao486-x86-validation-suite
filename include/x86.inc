; x86 Validation Suite - x86 CPU Definitions
; ============================================

%ifndef X86_INC
%define X86_INC

; CPU Types (from detection)
CPU_8086        equ 0
CPU_8088        equ 1
CPU_80186       equ 2
CPU_80188       equ 3
CPU_80286       equ 4
CPU_80386       equ 5
CPU_80486       equ 6
CPU_PENTIUM     equ 7       ; For future use

; FPU Types
FPU_NONE        equ 0
FPU_8087        equ 1
FPU_80287       equ 2
FPU_80387       equ 3
FPU_80486       equ 4       ; Integrated

; Control Register 0 (CR0) bits
CR0_PE          equ 0x00000001  ; Protection Enable
CR0_MP          equ 0x00000002  ; Monitor Coprocessor
CR0_EM          equ 0x00000004  ; Emulation
CR0_TS          equ 0x00000008  ; Task Switched
CR0_ET          equ 0x00000010  ; Extension Type
CR0_NE          equ 0x00000020  ; Numeric Error
CR0_WP          equ 0x00010000  ; Write Protect (486+)
CR0_AM          equ 0x00040000  ; Alignment Mask (486+)
CR0_NW          equ 0x20000000  ; Not Write-through (486+)
CR0_CD          equ 0x40000000  ; Cache Disable (486+)
CR0_PG          equ 0x80000000  ; Paging

; EFLAGS bits (386+)
EFLAGS_CF       equ 0x00000001
EFLAGS_PF       equ 0x00000004
EFLAGS_AF       equ 0x00000010
EFLAGS_ZF       equ 0x00000040
EFLAGS_SF       equ 0x00000080
EFLAGS_TF       equ 0x00000100
EFLAGS_IF       equ 0x00000200
EFLAGS_DF       equ 0x00000400
EFLAGS_OF       equ 0x00000800
EFLAGS_IOPL     equ 0x00003000
EFLAGS_NT       equ 0x00004000
EFLAGS_RF       equ 0x00010000  ; Resume Flag (386+)
EFLAGS_VM       equ 0x00020000  ; Virtual 8086 Mode (386+)
EFLAGS_AC       equ 0x00040000  ; Alignment Check (486+)
EFLAGS_VIF      equ 0x00080000  ; Virtual Interrupt (P5+)
EFLAGS_VIP      equ 0x00100000  ; Virtual Interrupt Pending (P5+)
EFLAGS_ID       equ 0x00200000  ; CPUID available (486+)

; Exception numbers
EXC_DE          equ 0       ; Divide Error
EXC_DB          equ 1       ; Debug
EXC_NMI         equ 2       ; NMI
EXC_BP          equ 3       ; Breakpoint
EXC_OF          equ 4       ; Overflow
EXC_BR          equ 5       ; BOUND Range Exceeded
EXC_UD          equ 6       ; Invalid Opcode
EXC_NM          equ 7       ; Device Not Available
EXC_DF          equ 8       ; Double Fault
EXC_CSO         equ 9       ; Coprocessor Segment Overrun (386)
EXC_TS          equ 10      ; Invalid TSS
EXC_NP          equ 11      ; Segment Not Present
EXC_SS          equ 12      ; Stack-Segment Fault
EXC_GP          equ 13      ; General Protection
EXC_PF          equ 14      ; Page Fault
EXC_MF          equ 16      ; x87 FPU Error
EXC_AC          equ 17      ; Alignment Check (486+)
EXC_MC          equ 18      ; Machine Check (P5+)

; Segment Descriptor Types (Protected Mode)
DESC_DATA_R     equ 0x00    ; Data, Read-Only
DESC_DATA_RW    equ 0x02    ; Data, Read/Write
DESC_DATA_RWA   equ 0x03    ; Data, Read/Write, Accessed
DESC_CODE_X     equ 0x08    ; Code, Execute-Only
DESC_CODE_XR    equ 0x0A    ; Code, Execute/Read
DESC_CODE_XRA   equ 0x0B    ; Code, Execute/Read, Accessed
DESC_CODE_XC    equ 0x0C    ; Code, Execute-Only, Conforming
DESC_CODE_XRC   equ 0x0E    ; Code, Execute/Read, Conforming

; System Descriptor Types
DESC_TSS16_AVL  equ 0x01    ; 16-bit TSS (Available)
DESC_LDT        equ 0x02    ; LDT
DESC_TSS16_BSY  equ 0x03    ; 16-bit TSS (Busy)
DESC_CALL16     equ 0x04    ; 16-bit Call Gate
DESC_TASK       equ 0x05    ; Task Gate
DESC_INT16      equ 0x06    ; 16-bit Interrupt Gate
DESC_TRAP16     equ 0x07    ; 16-bit Trap Gate
DESC_TSS32_AVL  equ 0x09    ; 32-bit TSS (Available)
DESC_TSS32_BSY  equ 0x0B    ; 32-bit TSS (Busy)
DESC_CALL32     equ 0x0C    ; 32-bit Call Gate
DESC_INT32      equ 0x0E    ; 32-bit Interrupt Gate
DESC_TRAP32     equ 0x0F    ; 32-bit Trap Gate

; Privilege levels
DPL_0           equ 0x00
DPL_1           equ 0x20
DPL_2           equ 0x40
DPL_3           equ 0x60

; Descriptor flags
DESC_PRESENT    equ 0x80
DESC_DPL_MASK   equ 0x60
DESC_S          equ 0x10    ; 0=System, 1=Code/Data

; High dword flags (386+)
DESC_G          equ 0x80    ; Granularity (4K pages)
DESC_DB         equ 0x40    ; Default size (32-bit)
DESC_L          equ 0x20    ; Long mode (64-bit, unused here)
DESC_AVL        equ 0x10    ; Available for software

; Page Table Entry bits
PTE_P           equ 0x001   ; Present
PTE_RW          equ 0x002   ; Read/Write
PTE_US          equ 0x004   ; User/Supervisor
PTE_PWT         equ 0x008   ; Page Write-Through (486+)
PTE_PCD         equ 0x010   ; Page Cache Disable (486+)
PTE_A           equ 0x020   ; Accessed
PTE_D           equ 0x040   ; Dirty
PTE_PS          equ 0x080   ; Page Size (4MB, unused here)

; GDT entry macro
%macro GDT_ENTRY 4
    ; %1 = base, %2 = limit, %3 = access, %4 = flags
    dw (%2) & 0xFFFF                    ; Limit 0:15
    dw (%1) & 0xFFFF                    ; Base 0:15
    db ((%1) >> 16) & 0xFF              ; Base 16:23
    db %3                               ; Access
    db ((%4) << 4) | (((%2) >> 16) & 0x0F) ; Flags + Limit 16:19
    db ((%1) >> 24) & 0xFF              ; Base 24:31
%endmacro

; IDT entry macro (32-bit)
%macro IDT_ENTRY 3
    ; %1 = offset, %2 = selector, %3 = type|DPL|P
    dw (%1) & 0xFFFF                    ; Offset 0:15
    dw %2                               ; Selector
    db 0                                ; Reserved
    db %3                               ; Type, DPL, Present
    dw ((%1) >> 16) & 0xFFFF            ; Offset 16:31
%endmacro

%endif ; X86_INC
