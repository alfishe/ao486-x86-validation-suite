;============================================================================
; DOS INC — DOS INT 21h function constants and PSP layout
;============================================================================
%ifndef DOS_INC
%define DOS_INC

; --- INT 21h function codes (AH values) ---
DOS_EXIT         equ 0x4C     ; exit with AL = return code
DOS_WRITE        equ 0x40     ; write to handle: BX=handle, CX=count, DS:DX=buf
DOS_CREATE       equ 0x3C     ; create/truncate file: CX=attr, DS:DX=asciiz
DOS_OPEN         equ 0x3D     ; open file: AL=mode, DS:DX=asciiz
DOS_CLOSE        equ 0x3E     ; close file: BX=handle
DOS_GET_DATE     equ 0x2A     ; get system date -> CX=year, DH=month, DL=day
DOS_GET_TIME     equ 0x2C     ; get system time -> CH=hr, CL=min, DH=sec, DL=1/100
DOS_SETVEC       equ 0x25     ; set interrupt vector: AL=vec, DS:DX=handler
DOS_GETVEC       equ 0x35     ; get interrupt vector: AL=vec -> ES:BX=handler
DOS_ALLOC        equ 0x48     ; allocate memory: BX=paragraphs -> AX=segment
DOS_FREE         equ 0x49     ; free memory: ES=segment
DOS_RESIZE       equ 0x4A     ; resize block: ES=segment, BX=new paragraphs

; --- Standard DOS handles ---
DOS_STDIN        equ 0
DOS_STDOUT       equ 1
DOS_STDERR       equ 2
DOS_STDAUX       equ 3         ; AUX (serial)
DOS_STDPRN       equ 4         ; PRN (printer)

; --- PSP layout (offsets from PSP segment) ---
PSP_INT20        equ 0x00      ; INT 20h opcode
PSP_MEM_END      equ 0x02      ; segment of end of memory
PSP_DOS_DISP     equ 0x05      ; long call to DOS dispatcher
PSP_PARENT_PSP   equ 0x16      ; parent PSP segment
PSP_HANDLE_TAB   equ 0x18      ; handle table (20 bytes)
PSP_ENV_SEG      equ 0x2C      ; environment segment
PSP_CMD_LEN      equ 0x80      ; command line length byte
PSP_CMD_LINE     equ 0x81      ; command line (127 bytes max, CR-terminated)

; --- File open modes ---
DOS_OPEN_RO      equ 0x00      ; read only
DOS_OPEN_WO      equ 0x01      ; write only
DOS_OPEN_RW      equ 0x02      ; read/write

; --- COM port register offsets (relative to base) ---
; COM1_BASE is defined in ports.inc
COM_IER          equ 1         ; Interrupt Enable Register
COM_IIR          equ 2         ; Interrupt Identification (R) / FIFO Control (W)
COM_LCR          equ 3         ; Line Control Register
COM_MCR          equ 4         ; Modem Control Register
COM_LSR          equ 5         ; Line Status Register
COM_MSR          equ 6         ; Modem Status Register
COM_SCR          equ 7         ; Scratch Register

; --- LSR bits ---
LSR_DR           equ 0x01      ; Data Ready
LSR_THRE         equ 0x20      ; Transmit Holding Register Empty
LSR_TEMT         equ 0x40      ; Transmitter Empty

%endif ; DOS_INC
