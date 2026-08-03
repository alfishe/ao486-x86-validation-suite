# Spec: 386 Call Gates & Privilege Transitions

## Metadata
- **Source file:** `src/cpu/80386/gates.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80386+ | ORACLE: manual
- **Impl-plan:** Phase 5, area `386-Gate`
- **Coverage:** [§7](../../coverage-matrix.md#7-cpu--80386-pri-1-32-bit--paging--v86)
- **Detail:** [external-integration.md §3](../../external-integration.md#3-singlesteptests80386protected)
- **Prerequisite:** [286-pm-infra.md](../80186-286/286-pm-infra.md)

## Purpose

Verify call gates: same-privilege CALL, more-privilege CALL (ring 3→0),
RETF from higher privilege, stack switching (SS0:ESP0 from TSS),
and parameter copying.

## GDT/IDT Gate Descriptor Format (386)

```
Call gate (8 bytes):
  Offset  Size  Field
  0       2     offset low 16 bits (target EIP)
  2       2     selector (target code segment)
  4       1     param count (low 5 bits) — for call gates only
  4       1     (upper 3 bits reserved, 0)
  5       1     access byte:
                bit 7: P (present)
                bits 5-6: DPL
                bit 4: S=0 (system)
                bits 0-3: type (0xC=32-bit call gate, 0x4=16-bit)
  6       2     offset high 16 bits (target EIP)
```

## Test Cases

### Same-privilege CALL through gate (CPL=0 → CPL=0)

| # | Gate DPL | Gate selector target | CPL | Expected | Notes |
|---|:--------:|---------------------|:---:|----------|-------|
| 1 | 0 | CODE_SEL0:handler | 0 | CALL succeeds, no stack switch | |
| 2 | 3 | CODE_SEL3:handler | 3 | CALL succeeds (CPL ≤ gate DPL) | |

### More-privilege CALL (ring 3 → ring 0)

| # | Gate DPL | Target DPL | CPL | Stack switch? | Expected | Notes |
|---|:--------:|:----------:|:---:|:------------:|----------|-------|
| 1 | 3 | 0 | 3 | yes | SS:ESP loaded from TSS SS0:ESP0 | key test |

When CPL changes from 3→0:
1. Old SS:ESP pushed onto new (ring 0) stack
2. Parameters copied from old stack (param count from gate)
3. CS:EIP pushed (with old CPL in RPL)
4. New CS:EIP loaded from gate
5. CPL = target code segment DPL

### Stack switching verification

| # | What to verify | How | Notes |
|---|---------------|-----|-------|
| 1 | SS0:ESP0 loaded from TSS | Read SS and ESP inside handler; compare to TSS SS0:ESP0 | |
| 2 | Old SS:ESP on new stack | Read [ESP+params+4] = old ESP, [ESP+params+8] = old SS | |
| 3 | Parameters copied | gate param count=2; verify 2 dwords from old stack appear on new stack | |

### RETF from higher privilege (ring 0 → ring 3)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | RETF from ring 0 handler | CPL restored to 3; SS:ESP popped from stack | |

> RETF checks: if RPL of return CS > CPL, perform stack switch (pop old SS:ESP).
> Verify: after RETF, SS and ESP match the values pushed during the CALL.

### Param count

| # | Gate param count | Old stack | New stack | Notes |
|---|:----------------:|-----------|-----------|-------|
| 1 | 0 | [ESP]=p1, [ESP+4]=p2 | params NOT copied | |
| 2 | 2 | [ESP]=p1, [ESP+4]=p2 | [newESP]=p1, [newESP+4]=p2 (before SS:ESP push) | 2 dwords copied |

### TSS stack pointer fields

```
TSS layout (386, 104 bytes min):
  Offset  Field
  0x04    ESP0 (prev task link for 286; 386: ESP0 starts here)
  0x04    Previous task link (16-bit)
  0x06    (reserved)
  0x08    ESP0
  0x0C    SS0
  0x10    ESP1
  0x14    SS1
  0x18    ESP2
  0x1C    SS2
  0x20    CR3
  0x24    EIP
  ...     (registers, etc.)
```

> The ring 0 stack pointer (SS0:ESP0) at TSS offset 0x08/0x0C is critical.
> Verify the CPU reads these correctly during a ring 3→0 transition.

### Gate type errors

| # | Gate type | Expected | Notes |
|---|-----------|----------|-------|
| 1 | 0x0C (32-bit call gate) | OK | |
| 2 | 0x04 (16-bit call gate) | OK but 16-bit stack ops | |
| 3 | 0x8E (interrupt gate) | CALL through it → **#GP** | wrong type for CALL |
| 4 | not-present gate (P=0) | **#NP** | |

## Pre/Post State (representative cases)

### Same-privilege CALL through gate (CPL=0 → CPL=0)
PRE (PM32, CPL=0):
  CS:EIP = CODE_SEL0:0x00001000
  ESP = 0x00080000
  GDT gate descriptor at selector 0x0020:
    offset = 0x00002000, selector = CODE_SEL0(0x0008), DPL=0
    type=0x0C (32-bit call gate), P=1, param_count=0
OP:  CALL FAR [0x0020:0x0000]  (or CALL 0x0020:0000)
POST:
  CS:EIP = CODE_SEL0:0x00002000  ← jumped to gate target
  CPL = 0 (unchanged)
  SS:ESP = unchanged (no stack switch for same privilege)
  Stack:
    [ESP-4] = 0x00001000  (return EIP)
    [ESP-8] = CODE_SEL0   (return CS)
  ESP = 0x0007FFF8

### More-privilege CALL (ring 3 → ring 0)
PRE (PM32, CPL=3):
  CS = CODE_SEL3(0x001B), RPL=3
  SS = DATA_SEL3(0x0023)
  ESP = 0x00070000
  EIP = 0x00001000
  GDT call gate at selector 0x0030: DPL=3, target=CODE_SEL0:0x00002000
  TSS SS0:ESP0 = 0x0010 : 0x00090000
  Old stack: [ESP+0]=param1=0x11111111, [ESP+4]=param2=0x22222222
  Gate param_count = 2
OP:  CALL 0x0030:0x0000  (through gate to ring 0)
POST:
  CS = CODE_SEL0(0x0008), CPL=0
  SS  = 0x0010, ESP = 0x00090000  ← loaded from TSS SS0:ESP0
  Ring 0 stack layout (growing down from 0x00090000):
    [ESP+0x00] = param1 = 0x11111111  ← copied from old stack
    [ESP+0x04] = param2 = 0x22222222
    [ESP+0x08] = old SS  = 0x0023
    [ESP+0x0C] = old ESP = 0x00070000
    [ESP+0x10] = old EFLAGS
    [ESP+0x14] = old CS  = 0x001B
    [ESP+0x18] = old EIP = 0x00001000

### RETF from ring 0 → ring 3
PRE (ring 0 handler stack after CALL from ring 3 above):
  CS:EIP = CODE_SEL0:0x00002050  (instruction after CALL in handler)
  Stack: [ESP]=ret_EIP, [ESP+4]=ret_CS(0x001B RPL=3),
         [ESP+8]=EFLAGS, [ESP+12]=old_ESP(0x00070000), [ESP+16]=old_SS(0x0023)
OP:  RETF
POST:
  CS = 0x001B, RPL=3  → CPL restored to 3
  EIP = return address in ring 3 code
  SS  = 0x0023, ESP = 0x00070000  ← popped from ring 0 stack
  ← RPL of return CS (3) > CPL (0) triggers stack switch back

### Not-present gate (P=0) → #NP
PRE:
  GDT call gate at 0x0040: P=0 (not present)
OP:  CALL 0x0040:0x0000
POST:
  #NP exception, error code = 0x0040

### Wrong gate type (interrupt gate used for CALL) → #GP
PRE:
  GDT descriptor at 0x0050: type=0x8E (32-bit interrupt gate, not call gate)
OP:  CALL 0x0050:0x0000
POST:
  #GP exception, error code = 0x0050

## State Save/Restore

- **Save:** SS, ESP, CS, EIP; TSS contents; GDT gate descriptors
- **Restore:** restore segment regs; restore TSS and GDT

## Pass/Fail Criteria

- **PASS:** ring transition works; stack switch correct; params copied
- **FAIL:** wrong CPL, SS:ESP, or missing params
- **SKIP:** GEN < 80386 (ring transitions exist on 286 but 32-bit TSS is 386+)
