; x86 Validation Suite - I/O Port Definitions
; =============================================

%ifndef PORTS_INC
%define PORTS_INC

; ===========================================================================
; 8259 Programmable Interrupt Controller (PIC)
; ===========================================================================

; Master PIC (IRQ 0-7)
PIC1_CMD        equ 0x20    ; Command port
PIC1_DATA       equ 0x21    ; Data port

; Slave PIC (IRQ 8-15)
PIC2_CMD        equ 0xA0    ; Command port
PIC2_DATA       equ 0xA1    ; Data port

; PIC Commands
PIC_EOI         equ 0x20    ; End of Interrupt
PIC_READ_IRR    equ 0x0A    ; Read IRR (Interrupt Request Register)
PIC_READ_ISR    equ 0x0B    ; Read ISR (In-Service Register)

; ICW1 bits
ICW1_INIT       equ 0x10    ; Initialization
ICW1_ICW4       equ 0x01    ; ICW4 needed
ICW1_SINGLE     equ 0x02    ; Single mode
ICW1_INTERVAL4  equ 0x04    ; Call address interval 4
ICW1_LEVEL      equ 0x08    ; Level triggered mode

; ICW4 bits
ICW4_8086       equ 0x01    ; 8086/88 mode
ICW4_AUTO       equ 0x02    ; Auto EOI
ICW4_BUF_SLAVE  equ 0x08    ; Buffered mode/slave
ICW4_BUF_MASTER equ 0x0C    ; Buffered mode/master
ICW4_SFNM       equ 0x10    ; Special fully nested

; ===========================================================================
; 8254 Programmable Interval Timer (PIT)
; ===========================================================================

PIT_CH0         equ 0x40    ; Channel 0 data port (system timer)
PIT_CH1         equ 0x41    ; Channel 1 data port (DRAM refresh)
PIT_CH2         equ 0x42    ; Channel 2 data port (speaker)
PIT_CTRL        equ 0x43    ; Control/Mode register

; Control word format
; Bits 7-6: Channel select (00=0, 01=1, 10=2, 11=read-back)
; Bits 5-4: Access mode (00=latch, 01=LSB, 10=MSB, 11=LSB+MSB)
; Bits 3-1: Mode (000-101)
; Bit 0: BCD (0=binary, 1=BCD)

PIT_SEL_CH0     equ 0x00
PIT_SEL_CH1     equ 0x40
PIT_SEL_CH2     equ 0x80
PIT_SEL_READBACK equ 0xC0

PIT_ACC_LATCH   equ 0x00
PIT_ACC_LOBYTE  equ 0x10
PIT_ACC_HIBYTE  equ 0x20
PIT_ACC_LOHI    equ 0x30

PIT_MODE_0      equ 0x00    ; Interrupt on Terminal Count
PIT_MODE_1      equ 0x02    ; Hardware Re-triggerable One-Shot
PIT_MODE_2      equ 0x04    ; Rate Generator
PIT_MODE_3      equ 0x06    ; Square Wave Generator
PIT_MODE_4      equ 0x08    ; Software Triggered Strobe
PIT_MODE_5      equ 0x0A    ; Hardware Triggered Strobe

PIT_FREQ        equ 1193182 ; Base frequency in Hz

; ===========================================================================
; 8237 DMA Controller
; ===========================================================================

; DMA Controller 1 (8-bit, channels 0-3)
DMA1_CH0_ADDR   equ 0x00    ; Channel 0 address
DMA1_CH0_COUNT  equ 0x01    ; Channel 0 count
DMA1_CH1_ADDR   equ 0x02    ; Channel 1 address
DMA1_CH1_COUNT  equ 0x03    ; Channel 1 count
DMA1_CH2_ADDR   equ 0x04    ; Channel 2 address
DMA1_CH2_COUNT  equ 0x05    ; Channel 2 count
DMA1_CH3_ADDR   equ 0x06    ; Channel 3 address
DMA1_CH3_COUNT  equ 0x07    ; Channel 3 count

DMA1_STAT_CMD   equ 0x08    ; Status (R) / Command (W)
DMA1_REQ        equ 0x09    ; Request register
DMA1_MASK_SING  equ 0x0A    ; Single channel mask
DMA1_MODE       equ 0x0B    ; Mode register
DMA1_FLIPFLOP   equ 0x0C    ; Clear byte flip-flop
DMA1_TEMP       equ 0x0D    ; Temp (R) / Master clear (W)
DMA1_MASK_CLR   equ 0x0E    ; Clear mask register
DMA1_MASK_ALL   equ 0x0F    ; All-channels mask register

; DMA Controller 2 (16-bit, channels 4-7)
DMA2_CH4_ADDR   equ 0xC0    ; Channel 4 address
DMA2_CH4_COUNT  equ 0xC2    ; Channel 4 count
DMA2_CH5_ADDR   equ 0xC4    ; Channel 5 address
DMA2_CH5_COUNT  equ 0xC6    ; Channel 5 count
DMA2_CH6_ADDR   equ 0xC8    ; Channel 6 address
DMA2_CH6_COUNT  equ 0xCA    ; Channel 6 count
DMA2_CH7_ADDR   equ 0xCC    ; Channel 7 address
DMA2_CH7_COUNT  equ 0xCE    ; Channel 7 count

DMA2_STAT_CMD   equ 0xD0    ; Status (R) / Command (W)
DMA2_REQ        equ 0xD2    ; Request register
DMA2_MASK_SING  equ 0xD4    ; Single channel mask
DMA2_MODE       equ 0xD6    ; Mode register
DMA2_FLIPFLOP   equ 0xD8    ; Clear byte flip-flop
DMA2_TEMP       equ 0xDA    ; Temp (R) / Master clear (W)
DMA2_MASK_CLR   equ 0xDC    ; Clear mask register
DMA2_MASK_ALL   equ 0xDE    ; All-channels mask register

; DMA page registers
DMA_PAGE_CH0    equ 0x87
DMA_PAGE_CH1    equ 0x83
DMA_PAGE_CH2    equ 0x81
DMA_PAGE_CH3    equ 0x82
DMA_PAGE_CH5    equ 0x8B
DMA_PAGE_CH6    equ 0x89
DMA_PAGE_CH7    equ 0x8A

; DMA mode bits
DMA_MODE_DEMAND  equ 0x00
DMA_MODE_SINGLE  equ 0x40
DMA_MODE_BLOCK   equ 0x80
DMA_MODE_CASCADE equ 0xC0

DMA_MODE_INCR    equ 0x00   ; Address increment
DMA_MODE_DECR    equ 0x20   ; Address decrement
DMA_MODE_AUTO    equ 0x10   ; Auto-init

DMA_MODE_VERIFY  equ 0x00   ; Verify transfer
DMA_MODE_WRITE   equ 0x04   ; Write transfer (to memory)
DMA_MODE_READ    equ 0x08   ; Read transfer (from memory)

; ===========================================================================
; 8042 Keyboard Controller
; ===========================================================================

KBC_DATA        equ 0x60    ; Data port
KBC_STAT_CMD    equ 0x64    ; Status (R) / Command (W)

; Status register bits
KBC_STAT_OBF    equ 0x01    ; Output buffer full
KBC_STAT_IBF    equ 0x02    ; Input buffer full
KBC_STAT_SYS    equ 0x04    ; System flag
KBC_STAT_CMD    equ 0x08    ; Command/data (0=data, 1=cmd)
KBC_STAT_TTO    equ 0x20    ; Transmit time-out
KBC_STAT_RTO    equ 0x40    ; Receive time-out
KBC_STAT_PERR   equ 0x80    ; Parity error

; Controller commands
KBC_CMD_READ_CONFIG  equ 0x20   ; Read configuration byte
KBC_CMD_WRITE_CONFIG equ 0x60   ; Write configuration byte
KBC_CMD_SELF_TEST    equ 0xAA   ; Controller self-test
KBC_CMD_PORT1_TEST   equ 0xAB   ; Test port 1
KBC_CMD_PORT1_DISABLE equ 0xAD  ; Disable port 1
KBC_CMD_PORT1_ENABLE equ 0xAE   ; Enable port 1
KBC_CMD_READ_OUTPUT  equ 0xD0   ; Read output port
KBC_CMD_WRITE_OUTPUT equ 0xD1   ; Write output port
KBC_CMD_PORT2_TEST   equ 0xA9   ; Test port 2
KBC_CMD_PORT2_DISABLE equ 0xA7  ; Disable port 2
KBC_CMD_PORT2_ENABLE equ 0xA8   ; Enable port 2

; Output port bits
KBC_OUT_A20     equ 0x02    ; A20 gate

; ===========================================================================
; MC146818 RTC / CMOS
; ===========================================================================

RTC_ADDR        equ 0x70    ; Address port
RTC_DATA        equ 0x71    ; Data port

; RTC/CMOS addresses
RTC_SECONDS     equ 0x00
RTC_SEC_ALARM   equ 0x01
RTC_MINUTES     equ 0x02
RTC_MIN_ALARM   equ 0x03
RTC_HOURS       equ 0x04
RTC_HR_ALARM    equ 0x05
RTC_DAY_WEEK    equ 0x06
RTC_DAY_MONTH   equ 0x07
RTC_MONTH       equ 0x08
RTC_YEAR        equ 0x09
RTC_STATUS_A    equ 0x0A
RTC_STATUS_B    equ 0x0B
RTC_STATUS_C    equ 0x0C
RTC_STATUS_D    equ 0x0D
RTC_CENTURY     equ 0x32    ; Some BIOSes

; ===========================================================================
; IDE/ATA
; ===========================================================================

IDE_PRI_BASE    equ 0x1F0   ; Primary IDE base
IDE_PRI_CTRL    equ 0x3F6   ; Primary IDE control
IDE_SEC_BASE    equ 0x170   ; Secondary IDE base
IDE_SEC_CTRL    equ 0x376   ; Secondary IDE control

; Register offsets from base
IDE_DATA        equ 0       ; Data register (16-bit)
IDE_ERROR       equ 1       ; Error register (R)
IDE_FEATURES    equ 1       ; Features register (W)
IDE_SECCOUNT    equ 2       ; Sector count
IDE_SECNUM      equ 3       ; Sector number / LBA low
IDE_CYLLO       equ 4       ; Cylinder low / LBA mid
IDE_CYLHI       equ 5       ; Cylinder high / LBA high
IDE_DRVHEAD     equ 6       ; Drive/Head
IDE_STATUS      equ 7       ; Status (R)
IDE_COMMAND     equ 7       ; Command (W)

; Control register offset
IDE_DEVCTRL     equ 0       ; Device control (at ctrl base)

; Status bits
IDE_STAT_ERR    equ 0x01
IDE_STAT_DRQ    equ 0x08
IDE_STAT_SRV    equ 0x10
IDE_STAT_DF     equ 0x20
IDE_STAT_DRDY   equ 0x40
IDE_STAT_BSY    equ 0x80

; Commands
IDE_CMD_IDENTIFY     equ 0xEC
IDE_CMD_READ_SEC     equ 0x20
IDE_CMD_WRITE_SEC    equ 0x30
IDE_CMD_PACKET       equ 0xA0
IDE_CMD_IDENTIFY_PKT equ 0xA1

; ===========================================================================
; VGA
; ===========================================================================

VGA_MISC_READ   equ 0x3CC   ; Miscellaneous output (R)
VGA_MISC_WRITE  equ 0x3C2   ; Miscellaneous output (W)
VGA_FEAT_READ   equ 0x3CA   ; Feature control (R)
VGA_FEAT_WRITE  equ 0x3DA   ; Feature control (W) - mono at 0x3BA
VGA_INPUT_0     equ 0x3C2   ; Input status 0
VGA_INPUT_1     equ 0x3DA   ; Input status 1 - mono at 0x3BA

; Sequencer
VGA_SEQ_ADDR    equ 0x3C4
VGA_SEQ_DATA    equ 0x3C5

; Graphics Controller
VGA_GC_ADDR     equ 0x3CE
VGA_GC_DATA     equ 0x3CF

; CRT Controller
VGA_CRTC_ADDR   equ 0x3D4   ; mono at 0x3B4
VGA_CRTC_DATA   equ 0x3D5   ; mono at 0x3B5

; Attribute Controller
VGA_AC_ADDR     equ 0x3C0   ; Also data write
VGA_AC_READ     equ 0x3C1   ; Data read

; DAC
VGA_DAC_MASK    equ 0x3C6
VGA_DAC_RADDR   equ 0x3C7   ; Read address
VGA_DAC_WADDR   equ 0x3C8   ; Write address
VGA_DAC_DATA    equ 0x3C9

; ===========================================================================
; Sound Devices
; ===========================================================================

; PC Speaker (PIT Channel 2 + Port 61h)
SPEAKER_CTRL    equ 0x61    ; System control port B

; AdLib / OPL2
ADLIB_ADDR      equ 0x388   ; Address port
ADLIB_DATA      equ 0x389   ; Data port
ADLIB_STATUS    equ 0x388   ; Status (R)

; Sound Blaster (base configurable, default 220h)
SB_BASE         equ 0x220   ; Default base
SB_RESET        equ 0x06    ; Reset (W)
SB_READ         equ 0x0A    ; Read data (R)
SB_WRITE        equ 0x0C    ; Write data/command (W)
SB_WSTAT        equ 0x0C    ; Write buffer status (R)
SB_RSTAT        equ 0x0E    ; Read buffer status (R)

; OPL3 (Sound Blaster Pro / 16)
OPL3_LEFT_ADDR  equ 0x388
OPL3_LEFT_DATA  equ 0x389
OPL3_RIGHT_ADDR equ 0x38A
OPL3_RIGHT_DATA equ 0x38B

; Gravis Ultrasound (base configurable, default 240h)
GUS_BASE        equ 0x240
GUS_MIDI_CTRL   equ 0x100   ; Offset from base
GUS_MIDI_DATA   equ 0x101
GUS_VOICE_SEL   equ 0x102
GUS_GF1_DATA_LO equ 0x104
GUS_GF1_DATA_HI equ 0x105

; MPU-401 (base configurable, default 330h)
MPU_DATA        equ 0x330   ; Data port
MPU_STAT_CMD    equ 0x331   ; Status (R) / Command (W)

; ===========================================================================
; Serial (8250/16550 UART)
; ===========================================================================

COM1_BASE       equ 0x3F8
COM2_BASE       equ 0x2F8
COM3_BASE       equ 0x3E8
COM4_BASE       equ 0x2E8

; Register offsets (DLAB=0)
UART_DATA       equ 0       ; Rx/Tx data
UART_IER        equ 1       ; Interrupt enable
UART_IIR        equ 2       ; Interrupt identification (R)
UART_FCR        equ 2       ; FIFO control (W, 16550+)
UART_LCR        equ 3       ; Line control
UART_MCR        equ 4       ; Modem control
UART_LSR        equ 5       ; Line status
UART_MSR        equ 6       ; Modem status
UART_SCRATCH    equ 7       ; Scratch register

; Register offsets (DLAB=1)
UART_DLL        equ 0       ; Divisor latch low
UART_DLH        equ 1       ; Divisor latch high

; Line Status Register bits
UART_LSR_DR     equ 0x01    ; Data ready
UART_LSR_OE     equ 0x02    ; Overrun error
UART_LSR_PE     equ 0x04    ; Parity error
UART_LSR_FE     equ 0x08    ; Framing error
UART_LSR_BI     equ 0x10    ; Break interrupt
UART_LSR_THRE   equ 0x20    ; Tx holding register empty
UART_LSR_TEMT   equ 0x40    ; Transmitter empty

; ===========================================================================
; Parallel (LPT)
; ===========================================================================

LPT1_BASE       equ 0x378
LPT2_BASE       equ 0x278
LPT3_BASE       equ 0x3BC   ; MDA adapter

LPT_DATA        equ 0       ; Data port
LPT_STATUS      equ 1       ; Status port
LPT_CONTROL     equ 2       ; Control port

%endif ; PORTS_INC
