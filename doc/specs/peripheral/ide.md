# Spec: IDE/ATA Controller

## Metadata
- **Source file:** `src/peripheral/ide/ide.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 7, area `IDE`
- **Coverage:** [§9.6](../../coverage-matrix.md#96-ideata)
- **Detail:** [prep-analysis §11](../../prep-analysis.md#11-ideata-stateful-behavior-matrix)
- **Refs:** [references.md](../../references.md) — ATA/ATAPI-7 (INCITS 397)

## Purpose

Verify IDE/ATA controller: BSY/DRQ/DRDY protocol, status vs alt-status (IRQ clear side
effect), IDENTIFY DEVICE layout, device selection and 400ns settle, READ SECTOR to scratch
media. ATAPI packet protocol is secondary.

**Constraint:** READ SECTOR to scratch LBA range only. No WRITE SECTOR without
explicit `/ide-write:allow` flag. IDENTIFY is always safe.

## Port Map (primary controller)

| Port | Register | Direction | Notes |
|------|----------|-----------|-------|
| 0x1F0 | Data (16-bit) | R/W | sector data transfer (PIO) |
| 0x1F1 | Error (R) / Features (W) | R/W | error details / command features |
| 0x1F2 | Sector count | R/W | number of sectors |
| 0x1F3 | LBA low / sector number | R/W | |
| 0x1F4 | LBA mid / cylinder low | R/W | |
| 0x1F5 | LBA high / cylinder high | R/W | |
| 0x1F6 | Device/head | W | bit 4 = DEV (0=master, 1=slave); bits 0–3 = head/LBA[24:27] |
| 0x1F7 | Status (R) / Command (W) | R/W | reading **clears IRQ** |
| 0x3F6 | Alternate status (R) / Device control (W) | R/W | reading does **NOT** clear IRQ |

### Status register (0x1F7 read / 0x3F6 read)

| Bit | Name | Meaning |
|:---:|------|---------|
| 7 | BSY | busy (controller executing command) |
| 6 | DRDY | device ready to accept command |
| 5 | DWF | device write fault |
| 4 | DSC | device seek complete |
| 3 | DRQ | data request (ready for data transfer) |
| 2 | CORR | corrected data |
| 1 | IDX | index |
| 0 | ERR | error (see error register) |

## Test Cases

### Device detection

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Select drive 0 (0x1F6, bit4=0), wait 400ns | DRDY should set | |
| 2 | Read status (0x1F7) | BSY=0 eventually | poll with timeout |
| 3 | Select drive 1 (0x1F6, bit4=1), wait 400ns | DRDY or absent | slave may not exist |

### IDENTIFY DEVICE (0xEC)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Select drive 0; OUT 0x1F7, 0xEC | BSY set | |
| 2 | Poll DRQ | DRQ=1 after BSY clears | |
| 3 | Read 256 words from 0x1F0 (REP INSW) | IDENTIFY data | verify word 0 = 0x00A0 (ATA) |

### IDENTIFY word verification

| Word | Content | Expected | Notes |
|:----:|---------|----------|-------|
| 0 | General config | 0x00A0 (ATA, non-removable) | |
| 49 | Capabilities | bit 9 = LBA supported | |
| 53 | Field validity | bit 0 = words 54–58 valid | |
| 60–61 | Max LBA28 sectors | ≥ scratch media size | 32-bit little-endian |
| 83 | Command sets | bit 10 = LBA48 supported | |

### Status vs alt-status IRQ clear

| # | Setup | Action | Expected | Notes |
|---|-------|--------|----------|-------|
| 1 | Issue IDENTIFY; wait for IRQ | read alt-status (0x3F6) | IRQ still pending | alt-status doesn't clear |
| 2 | (same) | read status (0x1F7) | **clears IRQ** | status read clears IRQ |

> **This is the signature IDE test.** An emulator that doesn't model the IRQ-clear
> side effect of reading 0x1F7 will break interrupt-driven drivers.

### Device selection 400ns settle

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Select drive 0 → read IDENTIFY | correct drive-0 data | |
| 2 | Select drive 1 → read IDENTIFY | drive-1 data (or absent) | |
| 3 | Switch drive, immediate status read | DRDY may be stale | need 400ns delay |

### READ SECTOR (0x20) — scratch media only

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Set sector count=1, LBA=scratch, issue 0x20 | BSY→DRQ | |
| 2 | Read 256 words | data sector | verify against known pattern |
| 3 | After last word | DRQ clears, BSY clears, IRQ fires | |

### Error conditions

| # | Setup | Expected | Notes |
|---|-------|----------|-------|
| 1 | Read beyond max LBA | ERR bit set, error reg = ABRT | |
| 2 | Issue command with no device | BSY then ERR, or signature read | |

## Pre/Post State (representative cases)

### IDENTIFY DEVICE (0xEC)
PRE:
  Drive 0 selected (port 0x1F6 bit4=0)
  Status (0x1F7) = 0x40   (DRDY=1, BSY=0, DRQ=0)
  Memory buffer at ES:DI = 0x0000 (512 bytes cleared)
OP:  OUT 0x1F7, 0xEC    ; issue IDENTIFY DEVICE
     ; poll 0x1F7 until BSY=0 and DRQ=1 (with timeout)
     MOV ECX, 128       ; 256 words
     REP INSW           ; read from port 0x1F0
POST:
  Buffer contains IDENTIFY data:
    Word 0   = 0x00A0   ← ATA device, non-removable
    Word 49  = bit 9 set ← LBA supported
    Word 60-61 = max LBA28 sectors
  Status = 0x40        ← DRDY=1, DRQ=0, BSY=0 (transfer complete)

### Status read clears IRQ (vs alt-status)
PRE:
  IDENTIFY issued, transfer complete
  IRQ line asserted (interrupt pending)
  Status register reads pending
OP (test alt-status first):
     IN AL, 0x3F6       ; read alt-status (does NOT clear IRQ)
     ; IRQ still pending
POST:
  AL = status byte (e.g., 0x40)
  IRQ = still pending  ← alt-status read preserves IRQ

OP (then read regular status):
     IN AL, 0x1F7       ; read status (DOES clear IRQ)
POST:
  AL = status byte (0x40)
  IRQ = cleared        ← status read at 0x1F7 acknowledges interrupt
  ← This side effect is the signature IDE emulator test

### READ SECTOR (0x20) — scratch media
PRE:
  Drive 0 selected
  Sector count (0x1F2) = 0x01
  LBA low (0x1F3)  = 0x00
  LBA mid (0x1F4)  = 0x00
  LBA high (0x1F5) = 0x00
  Device/head (0x1F6) = 0xE0  (LBA mode, drive 0, head 0)
  Status = 0x40 (DRDY=1)
OP:  OUT 0x1F7, 0x20    ; READ SECTOR command
     ; poll BSY→0, DRQ→1
     MOV ECX, 128
     REP INSW           ; read 256 words = 512 bytes
POST:
  Buffer contains sector data
  Status = 0x50        (DRDY=1, DRQ=0 — transfer complete)
  IRQ fires after last word

### Error — read beyond max LBA
PRE:
  Drive 0 selected
  LBA = beyond device capacity
OP:  OUT 0x1F2, 0x01    ; sector count = 1
     OUT 0x1F3, 0xFF    ; LBA low
     OUT 0x1F4, 0xFF    ; LBA mid
     OUT 0x1F5, 0xFF    ; LBA high
     OUT 0x1F7, 0x20    ; READ SECTOR
     ; poll BSY→0
     IN  AL, 0x1F7
POST:
  AL = 0x51            ← ERR bit (bit 0) set, DRDY=1
  IN AL, 0x1F1         ; read error register
  AL = 0x04            ← ABRT (bit 2) = command aborted

## State Save/Restore

- **Save:** selected drive, current LBA/sector count (if mid-transfer — abort first)
- **Restore:** re-select original drive; no register state to restore beyond that

## Pass/Fail Criteria

- **PASS:** IDENTIFY returns valid data; status clears IRQ; alt-status doesn't;
  READ SECTOR works on scratch media; device selection works
- **FAIL:** IRQ-clear side effect missing; DRQ stuck; wrong IDENTIFY data
- **SKIP:** if no IDE device present (detect first via IDENTIFY; report SKIP if absent)

## Known Divergences

- **No slave drive:** many emulators/cores only have master. Detect and SKIP gracefully.
- **ATAPI:** packet devices (CD-ROM) return word 0 = 0x00C0/0x85C0; separate code path.
- **Timeout values:** BSY clear time varies. Use generous timeout (1 second).
