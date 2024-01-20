.intel_syntax noprefix

.global supports_avx2
supports_avx2:
    mov eax, 1
    cpuid
    and ecx, 018000000H
    cmp ecx, 018000000H; check both OSXSAVE and AVX feature flags
    jne not_supported
    ; processor supports AVX instructions and XGETBV is enabled by OS
    mov eax, 7
    mov ecx, 0
    cpuid
    and ebx, 20H
    cmp ebx, 20H; check AVX2 feature flags
    jne not_supported
    mov ecx, 0; specify 0 for XCR0 register
    XGETBV; result in EDX:EAX
    and eax, 06H
    cmp eax, 06H; check OS has enabled both XMM and YMM state support
    jne not_supported
    mov eax, 1
    ret
NOT_SUPPORTED:
    mov eax, 0
    ret
