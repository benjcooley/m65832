# Licensing

This repository contains multiple components with different licenses.

## M65832 Original Work

All original M65832 code in the following directories is licensed under the
MIT License:

- `rtl/` - M65832 core RTL implementation
- `tb/` - Testbenches
- `docs/` - Documentation

```
MIT License

Copyright (c) 2026 Benjamin Cooley

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Reference Implementations

The `cores/` directory contains third-party reference implementations included
for study and comparison. These are **not** part of the M65832 original work
and retain their original licenses.

### MX65 - 6502 Core (`cores/6502-mx65/`)

A cycle-accurate 6502 core in VHDL by Steve Teal.

- **License**: MIT License
- **Copyright**: Copyright (c) 2022 Steve Teal
- **Source**: https://github.com/steveteal/mx65

See `cores/6502-mx65/LICENSE` for the full license text.

### SNES MiSTer - 65C816 Core (`cores/65816-mister/`)

A cycle-accurate SNES replica for the MiSTer platform by srg320, including
a 65C816 CPU implementation.

- **License**: GNU General Public License v3.0 (GPL-3.0)
- **Author**: srg320
- **Source**: https://github.com/MiSTer-devel/SNES_MiSTer

See `cores/65816-mister/LICENSE` for the full license text.

**Note**: The GPL-3.0 license applies only to the code within
`cores/65816-mister/`. This code is included as a reference and is not
combined with or linked into the M65832 implementation.

---

## Summary

| Directory | License | Notes |
|-----------|---------|-------|
| `rtl/`, `tb/`, `docs/` | MIT | M65832 original work |
| `cores/6502-mx65/` | MIT | Reference only |
| `cores/65816-mister/` | GPL-3.0 | Reference only |
