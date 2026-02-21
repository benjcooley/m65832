#!/usr/bin/env python3
"""
Convert VHDL testbench from old P register width encoding to new encoding.

Old scheme: M1:M0 at P[7:6], X1:X0 at P[5:4]
  - REP/SEP operated on M0,M1,X0,X1 via bits 4-7 of operand
  - SEP #$40 → set M0 (16-bit), REP #$40;SEP #$80 → M=10 (32-bit)

New scheme (thermometer W encoding):
  - N at P[7], V at P[6], M at P[5], X at P[4], W0 at P[8], W1 at P[9]
  - SEPE #$01 → W=01 (native), SEPE #$03 → W=11 (32-bit)
  - REP #$20 → clear M (16-bit acc), REP #$10 → clear X (16-bit idx)
  - SEPE works from emulation mode, so CLC;XCE is never needed as preamble
"""

import re
import sys


POKE_PAT = re.compile(
    r'(poke\s*\(\s*16#)([0-9A-Fa-f]+)(#\s*,\s*x")([0-9A-Fa-f]+)("\s*\))',
    re.IGNORECASE
)


def parse_test_blocks(filepath):
    """Parse VHDL file into test blocks with their line ranges."""
    with open(filepath) as f:
        lines = f.readlines()

    test_pat = re.compile(r'--+\s*TEST\s+(\d+[A-Za-z]?):\s*([^\n]+)', re.IGNORECASE)

    tests = []
    current_test = None
    current_start = None

    for i, line in enumerate(lines):
        m = test_pat.search(line)
        if m:
            if current_test is not None:
                tests.append((current_test, current_start, i))
            current_test = m.group(1)
            current_start = i

    if current_test is not None:
        tests.append((current_test, current_start, len(lines)))

    return lines, tests


def find_sub_programs(lines, start, end):
    """Split a test block into sub-programs separated by rst_n <= '0' lines.

    Returns list of (sub_start, sub_end) tuples for each sub-program's poke region.
    A sub-program is the set of poke lines between the previous rst_n/check_mem and the next rst_n.
    """
    rst_pat = re.compile(r"rst_n\s*<=\s*'0'", re.IGNORECASE)

    # Find all rst_n lines within this test
    rst_lines = []
    for i in range(start, end):
        if rst_pat.search(lines[i]):
            rst_lines.append(i)

    if not rst_lines:
        return [(start, end)]

    # Each sub-program is the poke region before each rst_n
    sub_programs = []
    for j, rst_line in enumerate(rst_lines):
        # Sub-program starts after previous rst_n (or at test start)
        if j == 0:
            sub_start = start
        else:
            sub_start = rst_lines[j-1]
        sub_end = rst_line
        sub_programs.append((sub_start, sub_end))

    return sub_programs


def extract_pokes_in_range(lines, start, end):
    """Extract poke calls from a line range, returning list of (line_idx, addr, data, match)."""
    pokes = []
    for i in range(start, end):
        for m in POKE_PAT.finditer(lines[i]):
            addr = int(m.group(2), 16)
            data = int(m.group(4), 16)
            pokes.append((i, addr, data, m))
    return pokes


def identify_mode_pattern(code):
    """Identify old-style mode entry pattern from byte map at $8000+.

    Returns: (pattern_name, pattern_length_bytes, replacement_bytes, description)
    or None if no conversion needed.
    """
    if 0x8000 not in code:
        return None

    b = [code.get(0x8000 + i, 0) for i in range(8)]

    # 8-byte: REP #$40; SEP #$80; REP #$10; SEP #$20 (32-bit M+X)
    if (b[0] == 0xC2 and b[1] == 0x40 and b[2] == 0xE2 and b[3] == 0x80 and
        b[4] == 0xC2 and b[5] == 0x10 and b[6] == 0xE2 and b[7] == 0x20):
        return ('32bit', 8, [0x02, 0x61, 0x03], 'SEPE #$03 -> W=11 (32-bit)')

    # 6-byte: CLC; XCE; REP #$40; SEP #$80 (native then 32-bit)
    if b[0] == 0x18 and b[1] == 0xFB and b[2] == 0xC2 and b[3] == 0x40 and b[4] == 0xE2 and b[5] == 0x80:
        return ('32bit', 6, [0x02, 0x61, 0x03], 'SEPE #$03 -> W=11 (32-bit)')

    # 6-byte: CLC; XCE; REP #$80; SEP #$40 (native 16-bit)
    if b[0] == 0x18 and b[1] == 0xFB and b[2] == 0xC2 and b[3] == 0x80 and b[4] == 0xE2 and b[5] == 0x40:
        return ('16bit_m', 6, [0x02, 0x61, 0x01, 0xC2, 0x20],
                'SEPE #$01 (W=01 native); REP #$20 (16-bit M)')

    # 4-byte: REP #$40; SEP #$80 (32-bit M)
    if b[0] == 0xC2 and b[1] == 0x40 and b[2] == 0xE2 and b[3] == 0x80:
        return ('32bit', 4, [0x02, 0x61, 0x03], 'SEPE #$03 -> W=11 (32-bit)')

    # 4-byte: REP #$10; SEP #$20 (32-bit X)
    if b[0] == 0xC2 and b[1] == 0x10 and b[2] == 0xE2 and b[3] == 0x20:
        return ('32bit', 4, [0x02, 0x61, 0x03], 'SEPE #$03 -> W=11 (32-bit)')

    # 4-byte: REP #$80; SEP #$40 (16-bit M)
    if b[0] == 0xC2 and b[1] == 0x80 and b[2] == 0xE2 and b[3] == 0x40:
        return ('16bit_m', 4, [0x02, 0x61, 0x01, 0xC2, 0x20],
                'SEPE #$01 (W=01); REP #$20 (16-bit M)')

    # 2-byte: SEP #$40 (16-bit M via set M0)
    if b[0] == 0xE2 and b[1] == 0x40:
        return ('16bit_m', 2, [0x02, 0x61, 0x01, 0xC2, 0x20],
                'SEPE #$01 (W=01); REP #$20 (16-bit M)')

    # 2-byte: SEP #$10 (16-bit X via set X0)
    if b[0] == 0xE2 and b[1] == 0x10:
        return ('16bit_x', 2, [0x02, 0x61, 0x01, 0xC2, 0x10],
                'SEPE #$01 (W=01); REP #$10 (16-bit X)')

    return None


def convert_sub_program(lines, sub_start, sub_end):
    """Convert a single sub-program's mode entry pattern. Returns (modified_lines, did_convert)."""
    pokes = extract_pokes_in_range(lines, sub_start, sub_end)
    if not pokes:
        return lines, False

    # Build byte map from pokes at $8000+
    code = {}
    for _, addr, data, _ in pokes:
        if 0x8000 <= addr < 0x8100:
            code[addr] = data

    pattern = identify_mode_pattern(code)
    if pattern is None:
        return lines, False

    pat_name, old_len, new_bytes, desc = pattern
    new_len = len(new_bytes)
    delta = new_len - old_len

    modified_lines = list(lines)

    # Find all poke lines in this sub-program and categorize them
    poke_lines_info = []
    for i in range(sub_start, sub_end):
        matches = list(POKE_PAT.finditer(modified_lines[i]))
        if matches:
            poke_info = []
            for m in matches:
                addr = int(m.group(2), 16)
                data = int(m.group(4), 16)
                poke_info.append((addr, data, m))
            poke_lines_info.append((i, poke_info))

    lines_to_replace = []
    lines_to_shift = []

    for line_idx, poke_info in poke_lines_info:
        has_mode_entry = any(0x8000 <= addr < 0x8000 + old_len for addr, _, _ in poke_info)
        has_code = any(addr >= 0x8000 + old_len for addr, _, _ in poke_info)
        has_data = any(addr < 0x8000 for addr, _, _ in poke_info)

        if has_mode_entry and not has_code and not has_data:
            lines_to_replace.append(line_idx)
        elif has_code or has_mode_entry:
            lines_to_shift.append((line_idx, poke_info))

    if not lines_to_replace and not lines_to_shift:
        return lines, False

    # Generate new mode-entry poke lines
    if lines_to_replace:
        first_line = modified_lines[lines_to_replace[0]]
        indent = re.match(r'^(\s*)', first_line).group(1)
    else:
        indent = '        '

    new_poke_lines = []
    new_poke_lines.append(f'{indent}-- {desc}\n')
    for i, byte_val in enumerate(new_bytes):
        addr = 0x8000 + i
        comment = ''
        if pat_name == '32bit':
            if i == 0: comment = '  -- SEPE #$03'
            elif i == 2: comment = '  -- set W1+W0 -> W=11 (32-bit)'
        elif pat_name == '16bit_m':
            if i == 0: comment = '  -- SEPE #$01'
            elif i == 2: comment = '  -- set W0 -> W=01 (native)'
            elif i == 3: comment = '  -- REP #$20'
            elif i == 4: comment = '  -- clear M -> 16-bit acc'
        elif pat_name == '16bit_x':
            if i == 0: comment = '  -- SEPE #$01'
            elif i == 2: comment = '  -- set W0 -> W=01 (native)'
            elif i == 3: comment = '  -- REP #$10'
            elif i == 4: comment = '  -- clear X -> 16-bit idx'

        new_poke_lines.append(
            f'{indent}poke(16#{addr:04X}#, x"{byte_val:02X}");{comment}\n'
        )

    # Shift addresses in subsequent poke lines
    if delta != 0:
        for line_idx, poke_info in lines_to_shift:
            line = modified_lines[line_idx]
            new_line = line
            for addr, data, match in reversed(poke_info):
                if addr >= 0x8000 + old_len:
                    new_addr = addr + delta
                    new_addr_str = f'{new_addr:04X}'
                    new_match = f'{match.group(1)}{new_addr_str}{match.group(3)}{match.group(4)}{match.group(5)}'
                    new_line = new_line[:match.start()] + new_match + new_line[match.end():]
            modified_lines[line_idx] = new_line

    # Replace mode-entry lines
    if lines_to_replace:
        first_replace = min(lines_to_replace)
        last_replace = max(lines_to_replace)

        # Also check: is the line before the first replace a comment about the old program?
        comment_line = first_replace - 1
        if comment_line >= sub_start:
            cl = modified_lines[comment_line].strip()
            if cl.startswith('--') and ('Program:' in cl or 'SEP' in cl or 'REP' in cl or 'M0' in cl or 'M1' in cl):
                first_replace = comment_line

        modified_lines[first_replace:last_replace + 1] = new_poke_lines

    return modified_lines, True


def convert_test(lines, test_id, start, end):
    """Convert a test block, handling multiple sub-programs (reset cycles)."""
    sub_programs = find_sub_programs(lines, start, end)

    any_converted = False
    # Process sub-programs in reverse order so line changes don't affect earlier indices
    for sub_start, sub_end in reversed(sub_programs):
        lines, did_convert = convert_sub_program(lines, sub_start, sub_end)
        if did_convert:
            any_converted = True

    return lines, any_converted


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    filepath = args[0] if args else '/Users/benjamincooley/projects/m65832/tb/tb_m65832_core.vhd'
    dry_run = '--dry-run' in sys.argv

    lines, tests = parse_test_blocks(filepath)

    converted = 0
    skipped = 0

    for test_id, start, end in reversed(tests):
        lines, did_convert = convert_test(lines, test_id, start, end)
        if did_convert:
            converted += 1
            print(f'  Converted test {test_id}', file=sys.stderr)
        else:
            skipped += 1

    print(f'Converted: {converted}, Skipped: {skipped}', file=sys.stderr)

    if not dry_run:
        with open(filepath, 'w') as f:
            f.writelines(lines)
        print(f'Written to {filepath}', file=sys.stderr)
    else:
        sys.stdout.writelines(lines)


if __name__ == '__main__':
    main()
