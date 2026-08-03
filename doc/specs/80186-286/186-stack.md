# Spec: 80186 ENTER/LEAVE Stack Frames

## Metadata
- **Source file:** `src/cpu/80186/stack.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 80186+ | ORACLE: manual
- **Impl-plan:** Phase 4, area `186-Stack`
- **Coverage:** [§5](../../coverage-matrix.md#5-cpu--80186-pri-3-thin-layer)

## Purpose

Verify ENTER/LEAVE instructions with all nesting levels (0-31), frame allocation,
and display pointer copying for nested procedure support.

## Prerequisites

- Stack with sufficient space (nesting level 31 requires ~66 bytes)
- BP initialized to known value

## ENTER Instruction Format

```
ENTER imm16, imm8
  imm16 = bytes to allocate for local variables (0-65535)
  imm8  = nesting level (0-31, higher bits ignored)
```

## Nesting Level Behavior

| Nesting | Display entries copied | Total stack usage | Use case |
|:-------:|:---------------------:|:-----------------:|----------|
| 0 | 0 | 2 + locals | Simple frame |
| 1 | 1 (current BP) | 4 + locals | One scope level |
| 2 | 2 | 6 + locals | Two scope levels |
| N | N | 2N + 2 + locals | N-1 display + frame pointer |

### Algorithm for ENTER (N > 0)

```
1. PUSH BP                      ; save old frame pointer
2. temp = SP                    ; save frame pointer location
3. if N > 1:
     for i = 1 to N-1:
       BP = BP - 2              ; point to previous display entry
       PUSH [SS:BP]             ; copy display pointer
4. PUSH temp                    ; push new frame pointer
5. BP = temp                    ; set BP to new frame
6. SP = SP - locals             ; allocate local space
```

## Test Cases

### ENTER nesting level 0 (simple frame)

| # | Locals | Initial SP | Initial BP | Final SP | Final BP | Stack layout |
|---|:------:|:----------:|:----------:|:--------:|:--------:|--------------|
| 1 | 0 | 0x1000 | 0x2000 | 0x0FFE | 0x0FFE | [0x0FFE]=old BP |
| 2 | 8 | 0x1000 | 0x2000 | 0x0FF6 | 0x0FFE | [0x0FFE]=old BP, 8 bytes locals |
| 3 | 256 | 0x1000 | 0x2000 | 0x0EFE | 0x0FFE | [0x0FFE]=old BP, 256 bytes locals |
| 4 | 65534 | 0xFFFF | 0x2000 | wrap | 0xFFFD | Maximum allocation |

### ENTER nesting level 1

| # | Locals | Initial SP | Initial BP | Final SP | Final BP | Display entries |
|---|:------:|:----------:|:----------:|:--------:|:--------:|-----------------|
| 1 | 0 | 0x1000 | 0x2000 | 0x0FFA | 0x0FFC | [0x0FFE]=old BP, [0x0FFC]=0x0FFC (self) |
| 2 | 8 | 0x1000 | 0x2000 | 0x0FF2 | 0x0FFC | + 8 bytes locals |

### ENTER nesting level 2

```
Initial: SP=0x1000, BP=0x2000, [0x1FFE]=0x3000 (enclosing frame's display)

After ENTER 4, 2:
  [0x0FFE] = 0x2000     ; old BP (pushed first)
  [0x0FFC] = 0x3000     ; copied display entry from [BP-2]
  [0x0FFA] = 0x0FFA     ; new frame pointer (temp)
  BP = 0x0FFA
  SP = 0x0FF6           ; 0x0FFA - 4 (locals)
```

### ENTER maximum nesting (31)

| # | Nesting | Stack usage (excluding locals) | Notes |
|---|:-------:|:------------------------------:|-------|
| 1 | 31 | 64 bytes (32 words) | 31 display + BP + frame ptr |

### LEAVE — restore frame

| # | Initial BP | Initial SP | [SS:BP] | Final BP | Final SP |
|---|:----------:|:----------:|:-------:|:--------:|:--------:|
| 1 | 0x0FFE | 0x0FF0 | 0x2000 | 0x2000 | 0x1000 |
| 2 | 0x0FFA | 0x0FF2 | 0x1000 | 0x1000 | 0x0FFC |

### ENTER/LEAVE round-trip

| # | Setup | ENTER | LEAVE | Verify |
|---|-------|-------|-------|--------|
| 1 | BP=0x2000, SP=0x1000 | ENTER 16, 0 | LEAVE | BP=0x2000, SP=0x1000 |
| 2 | nested frames | ENTER 8, 2 | LEAVE | display pointers preserved |

## Pre/Post State

### ENTER 8, 0 — simple frame

```
PRE:
  BP = 0x2000
  SP = 0x1000
  [SS:0x0FFE] = garbage

  OP:  ENTER 8, 0

POST:
  [SS:0x0FFE] = 0x2000     ← old BP saved
  BP = 0x0FFE              ← new frame pointer
  SP = 0x0FF6              ← BP - 8 (local space)
  Local vars at [SS:0x0FF6..0x0FFD]
```

### ENTER 4, 1 — one nesting level

```
PRE:
  BP = 0x2000              (current frame)
  SP = 0x1000

  OP:  ENTER 4, 1

POST:
  [SS:0x0FFE] = 0x2000     ← old BP (step 1)
  [SS:0x0FFC] = 0x0FFC     ← frame pointer (step 4: PUSH temp)
  BP = 0x0FFC              ← step 5
  SP = 0x0FF8              ← step 6: 0x0FFC - 4
```

### ENTER 0, 2 — two nesting levels with display copy

```
PRE:
  BP = 0x2000              (current frame)
  [SS:0x1FFE] = 0x3000     (enclosing frame's display entry)
  SP = 0x1000

  OP:  ENTER 0, 2

POST:
  [SS:0x0FFE] = 0x2000     ← old BP (step 1)
  temp = 0x0FFE            ← (step 2)
  ; step 3: loop for i=1 to 1 (N-1 = 1):
  ;   BP' = 0x2000 - 2 = 0x1FFE
  ;   PUSH [SS:0x1FFE] = 0x3000
  [SS:0x0FFC] = 0x3000     ← display entry copied
  [SS:0x0FFA] = 0x0FFE     ← frame pointer (step 4)
  BP = 0x0FFE              ← step 5
  SP = 0x0FFA              ← step 6 (0 locals)
```

### LEAVE — restore after ENTER

```
PRE:
  BP = 0x0FFE              (frame pointer)
  SP = 0x0FF6              (past locals)
  [SS:0x0FFE] = 0x2000     (saved old BP)

  OP:  LEAVE

POST:
  SP = 0x0FFE              ← SP = BP (step 1)
  BP = 0x2000              ← POP BP (step 2)
  SP = 0x1000              ← SP += 2 from POP
```

## Edge Cases

### ENTER with nesting level > 31

| # | Nesting byte | Effective nesting | Notes |
|---|:------------:|:-----------------:|-------|
| 1 | 0x20 (32) | 0 | Only low 5 bits used |
| 2 | 0x3F (63) | 31 | |
| 3 | 0xFF (255) | 31 | |

### ENTER with maximum locals (65535)

```
PRE:
  SP = 0x0000 (wrap case)
  BP = 0x2000

  OP:  ENTER 65534, 0

POST:
  SP wraps: 0x0000 - 2 - 65534 = 0x0000 (underflow handled)
```

### LEAVE with BP pointing to top of stack

```
PRE:
  BP = 0x0FFE
  SP = 0x0FFE              ← SP == BP (no locals)
  [SS:0x0FFE] = 0x2000

  OP:  LEAVE

POST:
  SP = 0x1000
  BP = 0x2000
```

## Flags

ENTER and LEAVE do **not** modify any flags.

## State Save/Restore

- **Save:** BP, SP, stack area, FLAGS
- **Restore:** restore BP, SP; verify stack area unchanged outside frame

## Known Divergences

| Behavior | 80186 | 286+ | Notes |
|----------|-------|------|-------|
| ENTER on 8086 | #UD | — | 8086 doesn't have ENTER |
| Stack wrap | wraps | may #SS | depends on stack limit |

## Pass/Fail Criteria

- **PASS:** BP/SP correct after ENTER/LEAVE; display pointers copied correctly
- **FAIL:** wrong BP, SP, or stack layout
- **SKIP:** GEN < 80186
