# addressing

Compute kernels that reach memory through the pointer shapes AIR producers emit:

- `undeclared_struct`: a buffer whose `air.arg_type_name` names a struct the module doesn't declare,
  read at a byte offset;
- `loaded_pointer`: a device pointer loaded from a buffer, then indexed;
- `pointer_select`, `pointer_phi`, `pointer_integer`: device pointers chosen by a `select`, carried
  around a loop by a `phi`, and converted to and from integers and compared with null.

Each thread writes one int, and the host compares it with the value the kernel's comment defines.
`check.sh` (registered with ctest) translates the library with `mtl2spv`, validates it with
`spirv-val`, and checks that each library in `refused/` fails with the message its source names.

## Provenance of the .metallib files

No Metal compiler was used. `shadersrc/addressing.ll` and `refused/*.ll` are hand-written AIR, wrapped
in the MTLB container Iridium reads:

    llvm-as shadersrc/addressing.ll -o addressing.air
    ../air-ops/make-metallib.py addressing.air addressing.metallib kernel:undeclared_struct kernel:loaded_pointer \
        kernel:pointer_select kernel:pointer_phi kernel:pointer_integer

Assemble with an LLVM no newer than the oldest Iridium supports (LLVM 19), since newer bitcode may
not be readable by an older one. These were assembled with LLVM 18.
