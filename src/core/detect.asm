;============================================================================
; MODULE: core/detect.asm
; DESC:   CPU and FPU feature detection (8086 .. Pentium, 8087 .. 486 FPU)
;
; DESIGN PRINCIPLE: Detect by BEHAVIOR, not by claimed identity.
; Emulators may claim to be a 486 but have 386-era bugs. We test actual
; feature presence via observable behavior differences.
;
; detect_cpu returns AL = one of CPU_8086..CPU_PENTIUM (see x86.inc)
; detect_fpu returns AL = one of FPU_NONE..FPU_80486  (see x86.inc)
;
; Additionally populates g_cpu_features and g_fpu_features bitmasks.
;
; All registers preserved except AX (result). Flags restored on exit.
;============================================================================

;---------------------------------------------------------------------------
; CPU feature bits (g_cpu_features)
;---------------------------------------------------------------------------
CPU_FEAT_PUSH_SP_NEW    equ 0x0001  ; PUSH SP pushes value before decrement (286+)
CPU_FEAT_NT_TOGGLE      equ 0x0002  ; NT flag (bit 14) can be toggled (386+)
CPU_FEAT_AC_TOGGLE      equ 0x0004  ; AC flag (bit 18) can be toggled (486+)
CPU_FEAT_ID_TOGGLE      equ 0x0008  ; ID flag (bit 21) can be toggled (CPUID present)
CPU_FEAT_CPUID          equ 0x0010  ; CPUID instruction works
CPU_FEAT_MSR            equ 0x0020  ; RDMSR/WRMSR available (Pentium+)
CPU_FEAT_TSC            equ 0x0040  ; RDTSC available

;---------------------------------------------------------------------------
; FPU feature bits (g_fpu_features)
;---------------------------------------------------------------------------
FPU_FEAT_PRESENT        equ 0x0001  ; FPU responds to FNINIT
FPU_FEAT_INF_PROJECTIVE equ 0x0002  ; +Inf == -Inf (387+ affine closure)
FPU_FEAT_FSIN           equ 0x0004  ; FSIN/FCOS available (387+)
FPU_FEAT_CW_037F        equ 0x0008  ; Default CW = 0x037F (387+), else 0x03FF
FPU_FEAT_INTEGRATED     equ 0x0010  ; On-die FPU (486DX+)

;---------------------------------------------------------------------------
; detect_cpu — Detect CPU generation by probing actual feature behavior
; OUT: AL = CPU type constant, g_cpu_features populated
;---------------------------------------------------------------------------
detect_cpu:
    push    bx
    push    cx
    push    si

    ; Clear feature flags
    xor     cx, cx                      ; CX = accumulated features

    ; Save original FLAGS
    pushf
    pop     si                          ; SI = original FLAGS

    ;========================================================================
    ; TEST 1: FLAGS bits 12-15 behavior
    ; 8086/8088: bits 12-15 are hardwired to 1, cannot be cleared
    ; 186+: bits 12-15 can be modified (IOPL/NT on 286+)
    ;========================================================================
    mov     ax, si
    and     ax, 0x0FFF                  ; attempt to clear bits 12-15
    push    ax
    popf
    pushf
    pop     ax
    and     ax, 0xF000                  ; isolate bits 12-15
    cmp     ax, 0xF000                  ; still all set?
    je      .is_8086                    ; yes → 8086/8088

    ; Restore FLAGS
    push    si
    popf

    ;========================================================================
    ; TEST 2: PUSH SP behavior (distinguishes 8086/186 from 286+)
    ; 8086/186: PUSH SP stores (SP-2), the value AFTER decrement
    ; 286+: PUSH SP stores SP, the value BEFORE decrement
    ;========================================================================
    mov     bx, sp                      ; save SP
    push    sp
    pop     ax
    cmp     ax, bx                      ; compare: pushed value vs original SP
    jne     .no_push_sp_new             ; AX != BX → old behavior (186)
    or      cx, CPU_FEAT_PUSH_SP_NEW    ; AX == BX → new behavior (286+)
.no_push_sp_new:

    ;========================================================================
    ; TEST 3: NT flag (bit 14) toggle
    ; 286: NT exists but cannot be toggled in real mode (always 0)
    ; 386+: NT can be toggled
    ;========================================================================
    mov     ax, si
    xor     ax, 0x4000                  ; toggle NT bit
    push    ax
    popf
    pushf
    pop     ax
    xor     ax, si                      ; what changed?
    test    ax, 0x4000                  ; did NT toggle?
    jz      .no_nt_toggle
    or      cx, CPU_FEAT_NT_TOGGLE
.no_nt_toggle:

    ; Restore FLAGS
    push    si
    popf

    ; If no NT toggle, we're 286 or 186
    test    cx, CPU_FEAT_NT_TOGGLE
    jz      .classify_pre386

    ;========================================================================
    ; TEST 4: AC flag (bit 18) toggle — requires 32-bit ops
    ; 386: AC bit is reserved, always 0
    ; 486+: AC can be toggled
    ;
    ; SAFETY: We only reach here if NT toggle worked, which means we're
    ; 386+. The 32-bit PUSHFD/POPFD instructions are safe to execute.
    ; On 8086/186/286, the NT test fails and we jump to .classify_pre386,
    ; never reaching this 32-bit code.
    ;========================================================================
    pushfd
    pop     ebx                         ; EBX = original EFLAGS

    mov     eax, ebx
    xor     eax, 0x00040000             ; toggle AC (bit 18)
    push    eax
    popfd
    pushfd
    pop     eax
    xor     eax, ebx
    test    eax, 0x00040000             ; did AC toggle?
    jz      .no_ac_toggle
    or      cx, CPU_FEAT_AC_TOGGLE
.no_ac_toggle:

    ;========================================================================
    ; TEST 5: ID flag (bit 21) toggle — indicates CPUID availability
    ; Early 486: ID bit reserved, always 0
    ; Late 486+: ID can be toggled, CPUID supported
    ;========================================================================
    mov     eax, ebx
    xor     eax, 0x00200000             ; toggle ID (bit 21)
    push    eax
    popfd
    pushfd
    pop     eax
    xor     eax, ebx
    test    eax, 0x00200000             ; did ID toggle?
    jz      .no_id_toggle
    or      cx, CPU_FEAT_ID_TOGGLE
.no_id_toggle:

    ; Restore EFLAGS
    push    ebx
    popfd

    ;========================================================================
    ; TEST 6: CPUID execution (if ID toggle succeeded)
    ;
    ; SAFETY: ID toggle success strongly indicates CPUID availability.
    ; However, some very early 486 steppings may have a broken CPUID.
    ; We store the CPUID result in memory to avoid issues with register
    ; clobbering (CPUID destroys EAX, EBX, ECX, EDX).
    ;========================================================================
    test    cx, CPU_FEAT_ID_TOGGLE
    jz      .cpuid_done

    ; BUGFIX: CPUID clobbers EAX, EBX, ECX, EDX. CX holds our accumulated
    ; feature flags — save to memory before CPUID, restore after.
    mov     [g_cpu_features], cx
    push    edx

    ; CPUID leaf 0 — get vendor and max leaf
    xor     eax, eax
    cpuid
    test    eax, eax                    ; max leaf >= 1?
    jz      .cpuid_restore

    or      word [g_cpu_features], CPU_FEAT_CPUID

    ; CPUID leaf 1 — get feature flags in EDX
    mov     eax, 1
    cpuid
    test    edx, 0x10                   ; TSC (bit 4)?
    jz      .no_tsc
    or      word [g_cpu_features], CPU_FEAT_TSC
.no_tsc:
    test    edx, 0x20                   ; MSR (bit 5)?
    jz      .cpuid_restore
    or      word [g_cpu_features], CPU_FEAT_MSR

.cpuid_restore:
    pop     edx
    mov     cx, [g_cpu_features]        ; restore feature flags

.cpuid_done:

    ;========================================================================
    ; Classification based on detected features
    ;========================================================================
    ; Store features
    mov     [g_cpu_features], cx

    ; Pentium+: CPUID with family >= 5, or MSR support
    test    cx, CPU_FEAT_MSR
    jnz     .is_pentium
    test    cx, CPU_FEAT_CPUID
    jz      .not_pentium_cpuid
    ; Check CPUID family — save CX since CPUID clobbers ECX
    push    ecx
    mov     eax, 1
    cpuid
    pop     ecx
    shr     eax, 8
    and     eax, 0x0F                   ; family
    cmp     al, 5
    jae     .is_pentium
.not_pentium_cpuid:

    ; 486: AC toggle works
    test    cx, CPU_FEAT_AC_TOGGLE
    jnz     .is_486

    ; 386: NT toggle works, AC doesn't
    test    cx, CPU_FEAT_NT_TOGGLE
    jnz     .is_386

.classify_pre386:
    ; 286 vs 186: PUSH SP behavior
    test    cx, CPU_FEAT_PUSH_SP_NEW
    jnz     .is_286
    jmp     .is_186

.is_8086:
    push    si
    popf
    mov     word [g_cpu_features], 0
    mov     al, CPU_8086
    jmp     .done

.is_186:
    mov     al, CPU_80186
    jmp     .done

.is_286:
    mov     al, CPU_80286
    jmp     .done

.is_386:
    mov     al, CPU_80386
    jmp     .done

.is_486:
    mov     al, CPU_80486
    jmp     .done

.is_pentium:
    mov     al, CPU_PENTIUM

.done:
    mov     [g_cpu_type], al
    pop     si
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
; detect_fpu — Detect FPU generation by probing actual behavior
; OUT: AL = FPU type constant, g_fpu_features populated
;
; BEHAVIOR-BASED DETECTION:
; 1. Check if FPU responds to FNINIT at all
; 2. Check default CW value: 0x03FF (8087/287) vs 0x037F (387/486)
; 3. Check infinity behavior: +Inf != -Inf (8087/287) vs +Inf == -Inf (387+)
; 4. Check FSIN availability (387+)
;---------------------------------------------------------------------------
detect_fpu:
    push    bx
    push    cx
    push    dx

    xor     cx, cx                      ; CX = accumulated FPU features

    ;========================================================================
    ; TEST 1: FPU presence — FNINIT + FNSTSW
    ; Write known pattern to SW buffer, execute FNINIT, read back SW.
    ; If FPU present, SW should be 0x0000 after FNINIT.
    ;========================================================================
    mov     word [detect_sw_buf], 0xFFFF    ; poison pattern

    fninit                              ; initialize FPU (no wait)

    ; Wait for FPU to complete — critical for external FPU
    ; Use memory-based sync: write to memory, read back
    mov     word [detect_cw_buf], 0
    fnstsw  [detect_sw_buf]             ; store status word

    ; Spin briefly for external FPU sync (FWAIT may hang if no FPU)
    mov     dx, 100
.fpu_wait:
    dec     dx
    jnz     .fpu_wait

    mov     ax, [detect_sw_buf]
    cmp     ax, 0xFFFF                  ; unchanged? no FPU
    je      .no_fpu
    test    ax, 0x00FF                  ; low byte should be 0
    jnz     .no_fpu

    or      cx, FPU_FEAT_PRESENT

    ;========================================================================
    ; TEST 2: Default control word value
    ; 8087/287: CW default = 0x03FF (PC=11, RC=00, all exceptions masked)
    ; 387/486:  CW default = 0x037F (PC=11→10 on 387, same masks)
    ;
    ; Actually: 8087 uses 0x03FF, 287 uses 0x03FF, 387+ uses 0x037F
    ; The difference is in the Precision Control field default.
    ;========================================================================
    fninit
    fnstcw  [detect_cw_buf]

    mov     dx, 100
.cw_wait:
    dec     dx
    jnz     .cw_wait

    mov     ax, [detect_cw_buf]
    cmp     ax, 0x037F
    jne     .not_037f
    or      cx, FPU_FEAT_CW_037F
.not_037f:

    ;========================================================================
    ; TEST 3: Infinity control behavior
    ; 8087/287 (projective): +Inf and -Inf are DIFFERENT (unsigned infinity)
    ; 387+ (affine):         +Inf and -Inf are THE SAME
    ;
    ; Method: Compare +1/0 vs -1/0, check condition codes
    ;========================================================================
    fninit                              ; clean state

    ; Generate +Infinity: 1.0 / 0.0
    fld1                                ; ST(0) = 1.0
    fldz                                ; ST(0) = 0.0, ST(1) = 1.0
    fdivp   st1, st0                    ; ST(0) = 1.0/0.0 = +Inf

    ; Generate -Infinity: -1.0 / 0.0
    fld1                                ; ST(0) = 1.0, ST(1) = +Inf
    fchs                                ; ST(0) = -1.0
    fldz                                ; ST(0) = 0.0, ST(1) = -1.0, ST(2) = +Inf
    fdivp   st1, st0                    ; ST(0) = -1.0/0.0 = -Inf, ST(1) = +Inf

    ; Compare -Inf (ST0) vs +Inf (ST1)
    fcompp                              ; compare and pop both
    fnstsw  ax                          ; get comparison result

    ; C3 (bit 14): 1 if equal, 0 if not equal
    ; 8087/287: +Inf != -Inf → C3=0
    ; 387+:     +Inf == -Inf → C3=1 (projective mode removed)
    test    ax, 0x4000                  ; test C3
    jz      .not_affine
    or      cx, FPU_FEAT_INF_PROJECTIVE ; actually means affine (387+)
.not_affine:

    ;========================================================================
    ; TEST 4: FSIN instruction availability (387+ only)
    ; On 8087/287, FSIN (D9 FE) is an invalid opcode.
    ;
    ; ROBUST DETECTION: Instead of relying on #UD handler (fragile),
    ; we use the infinity control (IC) bit and CW default as proxies.
    ; If infinity is affine (387+) AND CW default is 0x037F, FSIN exists.
    ;
    ; This avoids any risk of crashing on #UD.
    ;========================================================================

    ; FSIN exists on 387+ which has:
    ; - Affine infinity model (INF_PROJECTIVE flag set above)
    ; - Default CW = 0x037F
    test    cx, FPU_FEAT_INF_PROJECTIVE
    jz      .no_fsin
    test    cx, FPU_FEAT_CW_037F
    jz      .no_fsin

    ; Both conditions met — FSIN should be available
    ; Do a final sanity check: try FSIN in a protected way
    ; by checking FPU exception flags after execution

    fninit
    fldpi                               ; ST(0) = pi

    ; Mask all FPU exceptions to prevent crashes
    fnstcw  [detect_cw_buf]
    mov     ax, [detect_cw_buf]
    push    ax                          ; save original CW
    or      ax, 0x003F                  ; mask all exceptions
    mov     [detect_cw_buf], ax
    fldcw   [detect_cw_buf]

    ; Clear exception flags
    fclex

    ; Execute FSIN — if not supported, will set Invalid Operation
    ; On 8087/287 this may do nothing or set exception
    db      0xD9, 0xFE                  ; FSIN opcode

    ; Check for Invalid Operation exception
    fnstsw  ax
    test    ax, 0x0001                  ; IE (Invalid Operation)?
    jnz     .fsin_failed

    ; FSIN executed without exception — verify result sanity
    ; sin(pi) should be approximately 0
    fabs                                ; |sin(pi)|
    fld     dword [detect_epsilon]      ; 0.001
    fcompp
    fnstsw  ax
    test    ax, 0x4100                  ; C0 or C3 set = epsilon >= |sin(pi)|
    jz      .fsin_failed

    or      cx, FPU_FEAT_FSIN
    jmp     .fsin_restore_cw

.fsin_failed:
    ; Clean up FPU stack
    fstp    st0

.fsin_restore_cw:
    ; Restore original CW
    pop     ax
    mov     [detect_cw_buf], ax
    fldcw   [detect_cw_buf]

.no_fsin:

    ;========================================================================
    ; TEST 5: Check if FPU is integrated (486DX+)
    ; Integrated FPU has no external FPU wait states.
    ; Detection: Check CPU type — if 486+ with FPU, it's integrated.
    ;========================================================================
    mov     al, [g_cpu_type]
    cmp     al, CPU_80486
    jb      .not_integrated
    ; 486+ with working FPU = integrated (486DX, Pentium, etc.)
    or      cx, FPU_FEAT_INTEGRATED
.not_integrated:

    ;========================================================================
    ; Classification based on detected features
    ;========================================================================
    mov     [g_fpu_features], cx

    ; 486 integrated: FSIN + affine + integrated flag
    test    cx, FPU_FEAT_INTEGRATED
    jnz     .fpu_486

    ; 387: FSIN works, affine infinity
    test    cx, FPU_FEAT_FSIN
    jnz     .fpu_387

    ; 287 vs 8087: Both lack FSIN, both projective
    ; Distinguish by CW default? Both use 0x03FF actually.
    ; Distinguish by CPU: 286 → 287, 8086/186 → 8087
    mov     al, [g_cpu_type]
    cmp     al, CPU_80286
    je      .fpu_287
    cmp     al, CPU_80186
    je      .fpu_287                    ; 186 could have 8087 or 287
    jmp     .fpu_8087                   ; 8086 → 8087

.no_fpu:
    mov     word [g_fpu_features], 0
    mov     al, FPU_NONE
    jmp     .fpu_done

.fpu_8087:
    mov     al, FPU_8087
    jmp     .fpu_done

.fpu_287:
    mov     al, FPU_80287
    jmp     .fpu_done

.fpu_387:
    mov     al, FPU_80387
    jmp     .fpu_done

.fpu_486:
    mov     al, FPU_80486

.fpu_done:
    mov     [g_fpu_type], al

    ; Clean up FPU state
    fninit

    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
; Detection data (in code segment for .com compatibility)
;---------------------------------------------------------------------------
detect_cw_buf:      dw 0                ; FPU control word buffer
detect_sw_buf:      dw 0                ; FPU status word buffer
detect_epsilon:     dd 0.001            ; tolerance for FSIN check

;---------------------------------------------------------------------------
; Global detection results (must be in data segment or BSS)
;---------------------------------------------------------------------------
g_cpu_type:         db 0                ; CPU_8086 .. CPU_PENTIUM
g_fpu_type:         db 0                ; FPU_NONE .. FPU_80486
g_cpu_features:     dw 0                ; CPU_FEAT_* bitmask
g_fpu_features:     dw 0                ; FPU_FEAT_* bitmask
