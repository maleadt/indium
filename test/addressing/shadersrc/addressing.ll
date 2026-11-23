; Copyright (C) 2026 Darling Developers
;
; Hand-written AIR for the kernels in addressing.cpp, in the shapes Metal's compiler and LLVM's
; optimizer give pointer code. Every kernel takes the output buffer, an input buffer and the
; thread's position in the grid, and writes one int per thread. See README.md for how this becomes
; addressing.metallib.

source_filename = "addressing"
target datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v24:32:32-v32:32:32-v48:64:64-v64:64:64-v96:128:128-v128:128:128-v192:256:256-v256:256:256-v512:512:512-v1024:1024:1024-n8:16:32"
target triple = "air64-apple-macosx10.15.0"

; struct Params { int scale; int offset; }, named only in air.arg_type_name, as when the module
; declares no struct types: out[id] = params.offset + id
define void @undeclared_struct(ptr addrspace(1) %out, ptr addrspace(1) %params, i32 %id) #0 {
  %offsetp = getelementptr inbounds i8, ptr addrspace(1) %params, i64 4
  %offset = load i32, ptr addrspace(1) %offsetp, align 4
  %v = add i32 %offset, %id
  %i = zext i32 %id to i64
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %v, ptr addrspace(1) %o, align 4
  ret void
}

; struct Array { device int* data; long length; }: out[id] = array.data[id] * 2, through a pointer
; loaded from device memory
define void @loaded_pointer(ptr addrspace(1) %out, ptr addrspace(1) %array, i32 %id) #0 {
  %data = load ptr addrspace(1), ptr addrspace(1) %array, align 8
  %i = zext i32 %id to i64
  %p = getelementptr inbounds i32, ptr addrspace(1) %data, i64 %i
  %x = load i32, ptr addrspace(1) %p, align 4
  %v = shl i32 %x, 1
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %v, ptr addrspace(1) %o, align 4
  ret void
}

; out[id] = (id odd ? in : in + 32)[id], a select of two device pointers
define void @pointer_select(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
  %odd = trunc i32 %id to i1
  %upper = getelementptr inbounds i8, ptr addrspace(1) %in, i64 128
  %base = select i1 %odd, ptr addrspace(1) %in, ptr addrspace(1) %upper
  %i = zext i32 %id to i64
  %p = getelementptr inbounds i32, ptr addrspace(1) %base, i64 %i
  %v = load i32, ptr addrspace(1) %p, align 4
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %v, ptr addrspace(1) %o, align 4
  ret void
}

; out[id] = in[id] + in[id + 1] + in[id + 2] + in[id + 3], walking a pointer that a phi carries
; around the loop (the incoming value over the back edge is defined after the phi)
define void @pointer_phi(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
entry:
  %i = zext i32 %id to i64
  %start = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i
  br label %loop

loop:
  %p = phi ptr addrspace(1) [ %start, %entry ], [ %next, %loop ]
  %k = phi i32 [ 0, %entry ], [ %k1, %loop ]
  %sum = phi i32 [ 0, %entry ], [ %sum1, %loop ]
  %v = load i32, ptr addrspace(1) %p, align 4
  %sum1 = add i32 %sum, %v
  %next = getelementptr inbounds i8, ptr addrspace(1) %p, i64 4
  %k1 = add i32 %k, 1
  %done = icmp eq i32 %k1, 4
  br i1 %done, label %exit, label %loop

exit:
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %sum1, ptr addrspace(1) %o, align 4
  ret void
}

; out[id] = in == null ? -1 : in[id + 1], with the address computed as an integer
define void @pointer_integer(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
  %null = icmp eq ptr addrspace(1) %in, null
  %address = ptrtoint ptr addrspace(1) %in to i64
  %i = zext i32 %id to i64
  %i1 = add i64 %i, 1
  %offset = shl i64 %i1, 2
  %element = add i64 %address, %offset
  %p = inttoptr i64 %element to ptr addrspace(1)
  %v = load i32, ptr addrspace(1) %p, align 4
  %r = select i1 %null, i32 -1, i32 %v
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %r, ptr addrspace(1) %o, align 4
  ret void
}

@buf = internal addrspace(3) global [64 x i32] undef, align 4

; threadgroup int buf[64]; buf[id] = in[id]; buf[id + 32] = in[id + 32]; threadgroup int* p = buf + id;
; out[id] = p[1], a getelementptr on a derived pointer
define void @threadgroup_derived(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
  %i = zext i32 %id to i64
  %i32 = add i64 %i, 32
  %a = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i
  %b = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i32
  %va = load i32, ptr addrspace(1) %a, align 4
  %vb = load i32, ptr addrspace(1) %b, align 4
  %p = getelementptr inbounds [64 x i32], ptr addrspace(3) @buf, i64 0, i64 %i
  %q = getelementptr inbounds [64 x i32], ptr addrspace(3) @buf, i64 0, i64 %i32
  store i32 %va, ptr addrspace(3) %p, align 4
  store i32 %vb, ptr addrspace(3) %q, align 4
  call void @air.wg.barrier(i32 2, i32 1)
  %p1 = getelementptr inbounds i32, ptr addrspace(3) %p, i64 1
  %v = load i32, ptr addrspace(3) %p1, align 4
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %v, ptr addrspace(1) %o, align 4
  ret void
}

; int t[8], filled at byte offsets as LLVM 19+ writes constant indices; int* p = t + (id & 3);
; out[id] = p[0] + p[1] = in[id + k] + in[id + k + 1] with k = id & 3
define void @private_derived(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
entry:
  %t = alloca [8 x i32], align 4
  %i = zext i32 %id to i64
  %src = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i
  br label %fill

fill:
  %j = phi i64 [ 0, %entry ], [ %j1, %fill ]
  %s = getelementptr inbounds i32, ptr addrspace(1) %src, i64 %j
  %v = load i32, ptr addrspace(1) %s, align 4
  %byte = shl i64 %j, 2
  %d = getelementptr inbounds i8, ptr %t, i64 %byte
  store i32 %v, ptr %d, align 4
  %j1 = add i64 %j, 1
  %done = icmp eq i64 %j1, 8
  br i1 %done, label %read, label %fill

read:
  %k = and i64 %i, 3
  %p = getelementptr inbounds i32, ptr %t, i64 %k
  %a = load i32, ptr %p, align 4
  %p1 = getelementptr inbounds i8, ptr %p, i64 4
  %b = load i32, ptr %p1, align 4
  %sum = add i32 %a, %b
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %sum, ptr addrspace(1) %o, align 4
  ret void
}

@pool = internal addrspace(3) global [128 x i8] undef, align 4

; threadgroup memory as Metal.jl declares it, bytes read as ints: a 1-based index from a base 4 bytes
; before the pool, and a byte offset; out[id] = in[31 - id]
define void @threadgroup_bytes(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
  %i = zext i32 %id to i64
  %a = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i
  %v = load i32, ptr addrspace(1) %a, align 4
  %i1 = add i64 %i, 1
  %p = getelementptr i32, ptr addrspace(3) getelementptr (i8, ptr addrspace(3) @pool, i64 -4), i64 %i1
  store i32 %v, ptr addrspace(3) %p, align 4
  call void @air.wg.barrier(i32 2, i32 1)
  %r = sub i64 31, %i
  %byte = shl i64 %r, 2
  %q = getelementptr inbounds i8, ptr addrspace(3) @pool, i64 %byte
  %w = load i32, ptr addrspace(3) %q, align 4
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %w, ptr addrspace(1) %o, align 4
  ret void
}

@bytes = internal addrspace(3) global [32 x i8] undef, align 1

; a byte per thread, written next to the neighbours' bytes: out[id] = in[31 - id] & 0xff
define void @threadgroup_subword(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
  %i = zext i32 %id to i64
  %a = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i
  %v = load i32, ptr addrspace(1) %a, align 4
  %b = trunc i32 %v to i8
  %p = getelementptr inbounds i8, ptr addrspace(3) @bytes, i64 %i
  store i8 %b, ptr addrspace(3) %p, align 1
  call void @air.wg.barrier(i32 2, i32 1)
  %r = sub i64 31, %i
  %q = getelementptr inbounds i8, ptr addrspace(3) @bytes, i64 %r
  %w = load i8, ptr addrspace(3) %q, align 1
  %x = zext i8 %w to i32
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %x, ptr addrspace(1) %o, align 4
  ret void
}

@wide = internal addrspace(3) global [256 x i8] undef, align 4

; pointers into threadgroup memory chosen by a select and carried around a loop by a phi, and
; compared: out[id] = p == wide ? -1 : in[id] + ... + in[id + n - 1], where p = id odd ? wide + id : wide,
; n = 4 + (id & 3) (not a constant, so that the loop and its phi stay), and wide holds in[0..63]
define void @threadgroup_phi(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
entry:
  %i = zext i32 %id to i64
  %i32 = add i64 %i, 32
  %a = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i
  %b = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i32
  %va = load i32, ptr addrspace(1) %a, align 4
  %vb = load i32, ptr addrspace(1) %b, align 4
  %byte = shl i64 %i, 2
  %pi = getelementptr inbounds i8, ptr addrspace(3) @wide, i64 %byte
  %pj = getelementptr inbounds i8, ptr addrspace(3) %pi, i64 128
  store i32 %va, ptr addrspace(3) %pi, align 4
  store i32 %vb, ptr addrspace(3) %pj, align 4
  call void @air.wg.barrier(i32 2, i32 1)
  %odd = trunc i32 %id to i1
  %start = select i1 %odd, ptr addrspace(3) %pi, ptr addrspace(3) @wide
  %same = icmp eq ptr addrspace(3) %start, @wide
  %extra = and i32 %id, 3
  %n = add i32 %extra, 4
  br i1 %same, label %exit, label %loop

loop:
  %p = phi ptr addrspace(3) [ %start, %entry ], [ %next, %loop ]
  %k = phi i32 [ 0, %entry ], [ %k1, %loop ]
  %sum = phi i32 [ 0, %entry ], [ %sum1, %loop ]
  %v = load i32, ptr addrspace(3) %p, align 4
  %sum1 = add i32 %sum, %v
  %next = getelementptr inbounds i32, ptr addrspace(3) %p, i64 1
  %k1 = add i32 %k, 1
  %done = icmp eq i32 %k1, %n
  br i1 %done, label %exit, label %loop

exit:
  %r = phi i32 [ -1, %entry ], [ %sum1, %loop ]
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %r, ptr addrspace(1) %o, align 4
  ret void
}

@counter = internal addrspace(3) global [8 x i8] undef, align 4

; an atomic on an int at a byte offset into threadgroup memory: out[id] = 32
define void @threadgroup_atomic(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
entry:
  %c = getelementptr inbounds i8, ptr addrspace(3) @counter, i64 4
  %first = icmp eq i32 %id, 0
  br i1 %first, label %init, label %count

init:
  store i32 0, ptr addrspace(3) %c, align 4
  br label %count

count:
  call void @air.wg.barrier(i32 2, i32 1)
  %old = call i32 @air.atomic.local.add.s.i32(ptr addrspace(3) %c, i32 1, i32 0, i32 1, i1 true)
  call void @air.wg.barrier(i32 2, i32 1)
  %v = load i32, ptr addrspace(3) %c, align 4
  %i = zext i32 %id to i64
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %v, ptr addrspace(1) %o, align 4
  ret void
}

@mixed = internal addrspace(3) global [256 x i8] undef, align 4

; one byte pool holding floats at offset 0 and ints at offset 128, as Metal.jl lays out a struct
; of arrays: out[id] = 2 * in[(id + 1) & 31] + in[id]
define void @threadgroup_punning(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
  %i = zext i32 %id to i64
  %a = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i
  %v = load i32, ptr addrspace(1) %a, align 4
  %f = sitofp i32 %v to float
  %fp = getelementptr inbounds float, ptr addrspace(3) @mixed, i64 %i
  store float %f, ptr addrspace(3) %fp, align 4
  %ints = getelementptr inbounds i8, ptr addrspace(3) @mixed, i64 128
  %ip = getelementptr inbounds i32, ptr addrspace(3) %ints, i64 %i
  store i32 %v, ptr addrspace(3) %ip, align 4
  call void @air.wg.barrier(i32 2, i32 1)
  %n = add i32 %id, 1
  %n31 = and i32 %n, 31
  %j = zext i32 %n31 to i64
  %gp = getelementptr inbounds float, ptr addrspace(3) @mixed, i64 %j
  %g = load float, ptr addrspace(3) %gp, align 4
  %gi = fptosi float %g to i32
  %w = load i32, ptr addrspace(3) %ip, align 4
  %twice = shl i32 %gi, 1
  %r = add i32 %twice, %w
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %r, ptr addrspace(1) %o, align 4
  ret void
}

@union = internal addrspace(3) global [128 x i8] undef, align 8

; longs, byte tags and { int, char } structs in one pool, as Julia lays out a union: threads 0-3
; write long[id] = in[id] << 32 | id and struct[id] = { in[id], id } (8 bytes from offset 64), every
; thread writes tag[id] = id at offset 32; out[id] = in[k] + (31 - id) + in[3 - k] + (3 - k), k = id & 3
define void @threadgroup_mixed_width(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
entry:
  %i = zext i32 %id to i64
  %a = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i
  %v = load i32, ptr addrspace(1) %a, align 4
  %low = icmp ult i32 %id, 4
  br i1 %low, label %wide, label %tags

wide:
  %v64 = zext i32 %v to i64
  %hi = shl i64 %v64, 32
  %long = or i64 %hi, %i
  %lp = getelementptr inbounds i64, ptr addrspace(3) @union, i64 %i
  store i64 %long, ptr addrspace(3) %lp, align 8
  %t8 = trunc i32 %id to i8
  %s0 = insertvalue { i32, i8 } undef, i32 %v, 0
  %s1 = insertvalue { i32, i8 } %s0, i8 %t8, 1
  %sp = getelementptr inbounds { i32, i8 }, ptr addrspace(3) getelementptr inbounds (i8, ptr addrspace(3) @union, i64 64), i64 %i
  store { i32, i8 } %s1, ptr addrspace(3) %sp, align 4
  br label %tags

tags:
  %tag = trunc i32 %id to i8
  %tp = getelementptr inbounds i8, ptr addrspace(3) getelementptr inbounds (i8, ptr addrspace(3) @union, i64 32), i64 %i
  store i8 %tag, ptr addrspace(3) %tp, align 1
  call void @air.wg.barrier(i32 2, i32 1)
  %k = and i64 %i, 3
  %lq = getelementptr inbounds i64, ptr addrspace(3) @union, i64 %k
  %l = load i64, ptr addrspace(3) %lq, align 8
  %lhi = lshr i64 %l, 32
  %A = trunc i64 %lhi to i32
  %r = sub i64 31, %i
  %tq = getelementptr inbounds i8, ptr addrspace(3) getelementptr inbounds (i8, ptr addrspace(3) @union, i64 32), i64 %r
  %tv = load i8, ptr addrspace(3) %tq, align 1
  %B = zext i8 %tv to i32
  %m = sub i64 3, %k
  %sq = getelementptr inbounds { i32, i8 }, ptr addrspace(3) getelementptr inbounds (i8, ptr addrspace(3) @union, i64 64), i64 %m
  %sv = load { i32, i8 }, ptr addrspace(3) %sq, align 4
  %C = extractvalue { i32, i8 } %sv, 0
  %d8 = extractvalue { i32, i8 } %sv, 1
  %D = zext i8 %d8 to i32
  %AB = add i32 %A, %B
  %CD = add i32 %C, %D
  %res = add i32 %AB, %CD
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %res, ptr addrspace(1) %o, align 4
  ret void
}

; two halves read as one int, as Julia reads a struct of two Float16s (k = id & 1):
; t[k] = half(in[id]), t[1 - k] = half(in[id + 1]); out[id] = bits of t[0] | bits of t[1] << 16
define void @private_punning(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
  %t = alloca [2 x half], align 2
  %i = zext i32 %id to i64
  %a = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i
  %va = load i32, ptr addrspace(1) %a, align 4
  %i1 = add i64 %i, 1
  %b = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i1
  %vb = load i32, ptr addrspace(1) %b, align 4
  %ha = sitofp i32 %va to half
  %hb = sitofp i32 %vb to half
  %k = and i64 %i, 1
  %nk = xor i64 %k, 1
  %pa = getelementptr inbounds half, ptr %t, i64 %k
  store half %ha, ptr %pa, align 2
  %pb = getelementptr inbounds half, ptr %t, i64 %nk
  store half %hb, ptr %pb, align 2
  %bits = load i32, ptr %t, align 2
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %bits, ptr addrspace(1) %o, align 4
  ret void
}

@scratch = internal addrspace(3) global [16 x i8] undef, align 4
@copy = internal addrspace(3) global [16 x i8] undef, align 4

; threadgroup memory that is written and copied but never read: out[id] = in[id]
define void @threadgroup_dead(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
  %i = zext i32 %id to i64
  %a = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i
  %v = load i32, ptr addrspace(1) %a, align 4
  %k = and i64 %i, 3
  %p = getelementptr inbounds i32, ptr addrspace(3) @scratch, i64 %k
  store i32 %v, ptr addrspace(3) %p, align 4
  call void @llvm.memcpy.p3.p3.i64(ptr addrspace(3) align 4 @copy, ptr addrspace(3) align 4 @scratch, i64 16, i1 false)
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %v, ptr addrspace(1) %o, align 4
  ret void
}

; a pointer that may point into either of two private arrays, chosen by a phi, as Julia's mul!
; does with two structs: a[k] = in[id + k], b[k] = in[id + k + 8]; p = id odd ? a : b;
; out[id] = p[id & 3] + (p == a ? 1000 : 0)
define void @private_merged(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
entry:
  %a = alloca [4 x i32], align 4
  %b = alloca [4 x i32], align 4
  %i = zext i32 %id to i64
  %src = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i
  br label %fill

fill:
  %j = phi i64 [ 0, %entry ], [ %j1, %fill ]
  %sa = getelementptr inbounds i32, ptr addrspace(1) %src, i64 %j
  %va = load i32, ptr addrspace(1) %sa, align 4
  %j8 = add i64 %j, 8
  %sb = getelementptr inbounds i32, ptr addrspace(1) %src, i64 %j8
  %vb = load i32, ptr addrspace(1) %sb, align 4
  %da = getelementptr inbounds i32, ptr %a, i64 %j
  store i32 %va, ptr %da, align 4
  %db = getelementptr inbounds i32, ptr %b, i64 %j
  store i32 %vb, ptr %db, align 4
  %j1 = add i64 %j, 1
  %filled = icmp eq i64 %j1, 4
  br i1 %filled, label %choose, label %fill

choose:
  %odd = trunc i32 %id to i1
  br i1 %odd, label %useA, label %useB

useA:
  br label %read

useB:
  br label %read

read:
  %p = phi ptr [ %a, %useA ], [ %b, %useB ]
  %k = and i64 %i, 3
  %e = getelementptr inbounds i32, ptr %p, i64 %k
  %v = load i32, ptr %e, align 4
  %isA = icmp eq ptr %p, %a
  %bonus = select i1 %isA, i32 1000, i32 0
  %r = add i32 %v, %bonus
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %r, ptr addrspace(1) %o, align 4
  ret void
}

@first = internal addrspace(3) global [32 x i32] undef, align 4
@second = internal addrspace(3) global [32 x i32] undef, align 4

; a select of two threadgroup arrays: first[id] = in[id], second[id] = in[id + 32];
; out[id] = (id odd ? first : second)[31 - id]
define void @threadgroup_merged(ptr addrspace(1) %out, ptr addrspace(1) %in, i32 %id) #0 {
  %i = zext i32 %id to i64
  %i32 = add i64 %i, 32
  %a = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i
  %b = getelementptr inbounds i32, ptr addrspace(1) %in, i64 %i32
  %va = load i32, ptr addrspace(1) %a, align 4
  %vb = load i32, ptr addrspace(1) %b, align 4
  %pa = getelementptr inbounds [32 x i32], ptr addrspace(3) @first, i64 0, i64 %i
  store i32 %va, ptr addrspace(3) %pa, align 4
  %pb = getelementptr inbounds [32 x i32], ptr addrspace(3) @second, i64 0, i64 %i
  store i32 %vb, ptr addrspace(3) %pb, align 4
  call void @air.wg.barrier(i32 2, i32 1)
  %odd = trunc i32 %id to i1
  %q = select i1 %odd, ptr addrspace(3) @first, ptr addrspace(3) @second
  %r = sub i64 31, %i
  %e = getelementptr inbounds i32, ptr addrspace(3) %q, i64 %r
  %v = load i32, ptr addrspace(3) %e, align 4
  %o = getelementptr inbounds i32, ptr addrspace(1) %out, i64 %i
  store i32 %v, ptr addrspace(1) %o, align 4
  ret void
}

declare void @llvm.memcpy.p3.p3.i64(ptr addrspace(3) noalias nocapture writeonly, ptr addrspace(3) noalias nocapture readonly, i64, i1 immarg) #1
declare void @air.wg.barrier(i32, i32) #1
declare i32 @air.atomic.local.add.s.i32(ptr addrspace(3), i32, i32, i32, i1) #1

attributes #1 = { convergent nounwind }
attributes #0 = { nounwind }

!llvm.module.flags = !{!0}
!air.version = !{!1}
!air.language_version = !{!2}
!air.kernel = !{!10, !20, !30, !31, !32, !40, !41, !42, !43, !44, !45, !46, !47, !48, !49, !50, !51}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 2, i32 2, i32 0}
!2 = !{!"Metal", i32 2, i32 2, i32 0}
!3 = !{}
!4 = !{i32 0, !"air.buffer", !"air.location_index", i32 0, i32 1, !"air.read_write", !"air.arg_type_size", i32 4, !"air.arg_type_align_size", i32 4, !"air.arg_type_name", !"int", !"air.arg_name", !"out"}
!5 = !{i32 2, !"air.thread_position_in_grid", !"air.arg_type_name", !"uint", !"air.arg_name", !"id"}
!6 = !{i32 1, !"air.buffer", !"air.location_index", i32 1, i32 1, !"air.read", !"air.arg_type_size", i32 4, !"air.arg_type_align_size", i32 4, !"air.arg_type_name", !"int", !"air.arg_name", !"in"}

!10 = !{ptr @undeclared_struct, !3, !11}
!11 = !{!4, !12, !5}
!12 = !{i32 1, !"air.buffer", !"air.location_index", i32 1, i32 1, !"air.read", !"air.arg_type_size", i32 8, !"air.arg_type_align_size", i32 4, !"air.arg_type_name", !"Params", !"air.arg_name", !"params"}

!20 = !{ptr @loaded_pointer, !3, !21}
!21 = !{!4, !22, !5}
!22 = !{i32 1, !"air.buffer", !"air.location_index", i32 1, i32 1, !"air.read", !"air.arg_type_size", i32 16, !"air.arg_type_align_size", i32 8, !"air.arg_type_name", !"Array", !"air.arg_name", !"array"}

!7 = !{!4, !6, !5}
!30 = !{ptr @pointer_select, !3, !7}
!31 = !{ptr @pointer_phi, !3, !7}
!32 = !{ptr @pointer_integer, !3, !7}
!40 = !{ptr @threadgroup_derived, !3, !7}
!41 = !{ptr @private_derived, !3, !7}
!42 = !{ptr @threadgroup_bytes, !3, !7}
!43 = !{ptr @threadgroup_subword, !3, !7}
!44 = !{ptr @threadgroup_phi, !3, !7}
!45 = !{ptr @threadgroup_atomic, !3, !7}
!46 = !{ptr @threadgroup_punning, !3, !7}
!47 = !{ptr @threadgroup_mixed_width, !3, !7}
!48 = !{ptr @private_punning, !3, !7}
!49 = !{ptr @threadgroup_dead, !3, !7}
!50 = !{ptr @private_merged, !3, !7}
!51 = !{ptr @threadgroup_merged, !3, !7}
