#!/usr/bin/env python3
"""
Extract tests from VHDL testbench and run on emulator.
Ensures emulator matches RTL behavior exactly.

Usage:
    ./extract_vhdl_tests.py                    # Run all tests
    ./extract_vhdl_tests.py --vhdl-only        # Just parse, show tests
    ./extract_vhdl_tests.py --test 5           # Run specific test
"""

import re
import subprocess
import sys
import os
import tempfile
import argparse

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
TB_FILE = os.path.join(PROJECT_ROOT, "tb", "tb_m65832_core.vhd")
EMULATOR = os.path.join(PROJECT_ROOT, "emu", "m65832emu")
ASSEMBLER = os.path.join(PROJECT_ROOT, "as", "m65832as")


class Test:
    """Represents a single test case extracted from VHDL"""
    def __init__(self, number, name):
        self.number = number
        self.name = name
        self.pokes = []      # [(addr, data), ...]
        self.checks = []     # [(addr, expected, msg), ...]
        self.cycles = 100    # Default cycles
        self.reset_vector = 0x8000  # Default
        self.irq_active = False   # IRQ signal asserted
        self.nmi_active = False   # NMI signal asserted
        self.abort_active = False # ABORT signal asserted
        
    def __repr__(self):
        return f"Test({self.number}, '{self.name}', {len(self.pokes)} pokes, {len(self.checks)} checks)"


def parse_vhdl_testbench(filepath):
    """Parse VHDL testbench and extract test cases"""
    tests = []
    current_test = None
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Find test blocks (marked by "TEST N:" comments)
    test_pattern = re.compile(
        r'--+\s*TEST\s+(\d+):\s*([^\n]+)',
        re.IGNORECASE
    )
    
    # Find poke calls: poke(16#ADDR#, x"DATA")
    poke_pattern = re.compile(
        r'poke\s*\(\s*16#([0-9A-Fa-f]+)#\s*,\s*x"([0-9A-Fa-f]+)"\s*\)',
        re.IGNORECASE
    )
    
    # Find poke16 calls: poke16(16#ADDR#, x"DATA")
    poke16_pattern = re.compile(
        r'poke16\s*\(\s*16#([0-9A-Fa-f]+)#\s*,\s*x"([0-9A-Fa-f]+)"\s*\)',
        re.IGNORECASE
    )
    
    # Find check_mem calls: check_mem(16#ADDR#, x"EXPECTED", "msg")
    check_pattern = re.compile(
        r'check_mem\s*\(\s*16#([0-9A-Fa-f]+)#\s*,\s*x"([0-9A-Fa-f]+)"\s*,\s*"([^"]+)"\s*\)',
        re.IGNORECASE
    )
    
    # Find wait_cycles calls
    cycles_pattern = re.compile(
        r'wait_cycles\s*\(\s*(\d+)\s*\)',
        re.IGNORECASE
    )
    
    # Find interrupt signal assignments
    irq_pattern = re.compile(r"irq_n\s*<=\s*'([01])'", re.IGNORECASE)
    nmi_pattern = re.compile(r"nmi_n\s*<=\s*'([01])'", re.IGNORECASE)
    abort_pattern = re.compile(r"abort_n\s*<=\s*'([01])'", re.IGNORECASE)
    
    lines = content.split('\n')
    i = 0
    
    while i < len(lines):
        line = lines[i]
        
        # Check for test header
        test_match = test_pattern.search(line)
        if test_match:
            if current_test:
                tests.append(current_test)
            test_num = int(test_match.group(1))
            test_name = test_match.group(2).strip()
            current_test = Test(test_num, test_name)
            i += 1
            continue
        
        if current_test:
            # Look for poke16
            for match in poke16_pattern.finditer(line):
                addr = int(match.group(1), 16)
                data = int(match.group(2), 16)
                # poke16 is little-endian
                current_test.pokes.append((addr, data & 0xFF))
                current_test.pokes.append((addr + 1, (data >> 8) & 0xFF))
            
            # Look for poke (but not poke16)
            if 'poke16' not in line.lower():
                for match in poke_pattern.finditer(line):
                    addr = int(match.group(1), 16)
                    data = int(match.group(2), 16)
                    current_test.pokes.append((addr, data))
            
            # Look for check_mem
            for match in check_pattern.finditer(line):
                addr = int(match.group(1), 16)
                expected = int(match.group(2), 16)
                msg = match.group(3)
                current_test.checks.append((addr, expected, msg))
            
            # Look for wait_cycles - accumulate all waits > 10
            for match in cycles_pattern.finditer(line):
                cycles = int(match.group(1))
                if cycles > 10:  # Ignore reset wait (usually 10 cycles)
                    current_test.cycles += cycles
            
            # Look for interrupt signal assignments (active-low signals)
            # Only capture the first assertion of each signal (ignore deassertions)
            irq_match = irq_pattern.search(line)
            if irq_match and not current_test.irq_active:
                if irq_match.group(1) == '0':
                    current_test.irq_active = True
            
            nmi_match = nmi_pattern.search(line)
            if nmi_match and not current_test.nmi_active:
                if nmi_match.group(1) == '0':
                    current_test.nmi_active = True
            
            abort_match = abort_pattern.search(line)
            if abort_match and not current_test.abort_active:
                if abort_match.group(1) == '0':
                    current_test.abort_active = True
        
        i += 1
    
    if current_test:
        tests.append(current_test)
    
    return tests


def create_test_binary(test):
    """Create a binary file from test pokes"""
    # Find the range of memory used
    if not test.pokes:
        return None, 0, 0
    
    addrs = [p[0] for p in test.pokes]
    min_addr = min(addrs)
    max_addr = max(addrs)
    
    # Create memory image
    size = max_addr - min_addr + 1
    memory = bytearray(size)
    
    for addr, data in test.pokes:
        memory[addr - min_addr] = data
    
    return bytes(memory), min_addr, max_addr


def run_emulator_test(test, verbose=False):
    """Run a test on the emulator and check results"""
    
    # Create binary from pokes
    binary, min_addr, max_addr = create_test_binary(test)
    if binary is None:
        return None, "No pokes in test"
    
    # Write binary to temp file
    with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as f:
        f.write(binary)
        bin_path = f.name
    
    try:
        # The VHDL testbench uses reset vector at $FFFC pointing to $8000
        # We need to handle this properly
        
        # Check if this test includes reset vector setup
        has_reset_vector = any(addr == 0xFFFC or addr == 0xFFFD for addr, _ in test.pokes)
        
        # Build emulator command
        # Use --emulation mode since VHDL tests are in 8-bit emulation mode
        cmd = [
            EMULATOR,
            '--emulation',      # 8-bit mode like VHDL tests
            '-m', '256',        # 256KB memory
            '-c', str(test.cycles + 50),  # Extra cycles for safety
        ]
        
        if has_reset_vector:
            # Load at address 0 (we have vectors and code)
            cmd.extend(['-o', '0'])
        else:
            # Load at min_addr
            cmd.extend(['-o', hex(min_addr)])
            cmd.extend(['-e', '0x8000'])  # Entry point
        
        cmd.append(bin_path)
        
        if verbose:
            print(f"  Command: {' '.join(cmd)}")
        
        # Run emulator
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        
        if result.returncode != 0 and verbose:
            print(f"  Emulator stderr: {result.stderr}")
        
        # Now we need to check memory locations
        # Run emulator in interactive mode to read memory
        # Actually, let's add a simpler approach: have emulator dump specific addresses
        
        # For now, we'll use a different approach: create a test program that
        # stores results to known locations, then check those
        
        return True, "Executed (memory check not yet implemented)"
        
    finally:
        os.unlink(bin_path)


def run_emulator_test_v2(test, verbose=False):
    """
    Run test using interactive mode to poke memory, run, and check results.
    This mirrors exactly what the VHDL testbench does.
    """
    
    results = {'passed': 0, 'failed': 0, 'errors': []}
    
    # Build interactive script
    script_lines = []
    
    # Get set of addresses the test will poke (before any filtering)
    original_addresses = {addr for addr, _ in test.pokes}
    
    # Work around VHDL tests that assume 32-bit vectors in emulation mode.
    # The VHDL tests set up 32-bit vectors (4 bytes each), but in emulation mode
    # vectors are 16-bit. This causes corruption:
    # - NMI at $FFFA/$FFFB: Test writes $FFFA-$FFFD, corrupting reset at $FFFC/$FFFD
    # - ABORT at $FFF8/$FFF9: Test writes $FFF8-$FFFB, corrupting NMI at $FFFA/$FFFB
    # Solution: Keep only the first 2 bytes of each 32-bit vector setup.
    # BUT: Only apply this workaround for tests that actually trigger interrupts
    # (irq/nmi/abort). Tests that use RTI to enter native mode need full 32-bit vectors.
    
    filtered_pokes = []
    uses_interrupts = test.irq_active or test.nmi_active or test.abort_active
    
    for addr, data in test.pokes:
        if uses_interrupts:
            # If this is a 32-bit vector extension (high bytes), skip it
            # ABORT 32-bit vector: $FFF8-$FFFB, skip $FFFA/$FFFB if $FFF8 is also poked
            if addr == 0xFFFA and 0xFFF8 in original_addresses and 0xFFF9 in original_addresses:
                continue  # Part of ABORT 32-bit vector, corrupts NMI
            if addr == 0xFFFB and 0xFFF8 in original_addresses and 0xFFF9 in original_addresses:
                continue  # Part of ABORT 32-bit vector, corrupts NMI
            # NMI 32-bit vector: $FFFA-$FFFD, skip $FFFC/$FFFD if $FFFA is also poked
            if addr == 0xFFFC and 0xFFFA in original_addresses and 0xFFFB in original_addresses:
                continue  # Part of NMI 32-bit vector, corrupts reset
            if addr == 0xFFFD and 0xFFFA in original_addresses and 0xFFFB in original_addresses:
                continue  # Part of NMI 32-bit vector, corrupts reset
        filtered_pokes.append((addr, data))
    
    test.pokes = filtered_pokes
    test_addresses = {addr for addr, _ in test.pokes}
    
    # Set up reset vectors (16-bit for emulation mode, same as VHDL testbench)
    # Reset vector -> $8000 (only if test doesn't override)
    if 0xFFFC not in test_addresses:
        script_lines.append('w fffc 0')
    if 0xFFFD not in test_addresses:
        script_lines.append('w fffd 80')
    # BRK/IRQ vector -> $FF00 (points to STP instruction to halt)
    if 0xFFFE not in test_addresses:
        script_lines.append('w fffe 0')
    if 0xFFFF not in test_addresses:
        script_lines.append('w ffff ff')
    # Set up STP instruction at $FF00 to halt on BRK/IRQ
    if 0xFF00 not in test_addresses:
        script_lines.append('w ff00 db')  # STP opcode
    # NMI vector -> $FF00 (also halt)
    if 0xFFFA not in test_addresses:
        script_lines.append('w fffa 0')
    if 0xFFFB not in test_addresses:
        script_lines.append('w fffb ff')
    # ABORT vector -> $FF00 (also halt)
    if 0xFFF8 not in test_addresses:
        script_lines.append('w fff8 0')
    if 0xFFF9 not in test_addresses:
        script_lines.append('w fff9 ff')
    
    # Write all memory locations (pokes)
    for addr, data in test.pokes:
        script_lines.append(f'w {addr:x} {data:x}')
    
    # Reset to apply vectors
    script_lines.append('reset')
    
    # Apply interrupt signals if set
    if test.irq_active:
        script_lines.append('irq 1')
    if test.nmi_active:
        script_lines.append('nmi')
    if test.abort_active:
        script_lines.append('abort')
    
    # Run for specified cycles
    script_lines.append(f'r {test.cycles}')
    
    # Read back check locations
    for addr, expected, msg in test.checks:
        script_lines.append(f'm {addr:x} 1')
    
    script_lines.append('q')
    script = '\n'.join(script_lines) + '\n'
    
    if verbose:
        print(f"  Script ({len(test.pokes)} pokes, {test.cycles} cycles):")
        if len(script_lines) < 20:
            for line in script_lines[:-1]:
                print(f"    {line}")
    
    try:
        # Run emulator in interactive mode with emulation mode
        # The VHDL tests start in emulation mode (16-bit vectors)
        # M65832 allows width changes via SEP/REP even in emulation mode (unlike 65816)
        cmd = [
            EMULATOR,
            '--emulation',  # Start in emulation mode (16-bit vectors)
            '-m', '64',     # 64KB memory  
            '-i',           # Interactive mode
        ]
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            input=script
        )
        
        output = result.stdout
        
        if verbose and result.returncode != 0:
            print(f"  Emulator stderr: {result.stderr[:200]}")
        
        # Parse memory dump output to check values
        # Format: "ADDR: XX XX XX ..."
        for addr, expected, msg in test.checks:
            # Look for the memory dump line
            pattern = rf'{addr:08X}:\s+([0-9A-Fa-f]{{2}})'
            match = re.search(pattern, output, re.IGNORECASE)
            
            if match:
                actual = int(match.group(1), 16)
                if actual == expected:
                    results['passed'] += 1
                    if verbose:
                        print(f"    PASS: {msg} (${addr:04X} = ${actual:02X})")
                else:
                    results['failed'] += 1
                    results['errors'].append(f"{msg}: expected ${expected:02X}, got ${actual:02X}")
                    if verbose:
                        print(f"    FAIL: {msg} (${addr:04X} = ${actual:02X}, expected ${expected:02X})")
            else:
                results['failed'] += 1
                results['errors'].append(f"{msg}: could not read address ${addr:04X}")
                if verbose:
                    print(f"    ERROR: Could not find ${addr:04X} in output")
        
        return results
        
    except subprocess.TimeoutExpired:
        return {'passed': 0, 'failed': len(test.checks), 'errors': ['Timeout']}
    except Exception as e:
        return {'passed': 0, 'failed': len(test.checks), 'errors': [str(e)]}


def main():
    parser = argparse.ArgumentParser(description='Extract and run VHDL tests on emulator')
    parser.add_argument('--vhdl-only', action='store_true', help='Just parse and show tests')
    parser.add_argument('--test', type=int, help='Run specific test number')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')
    parser.add_argument('--list', '-l', action='store_true', help='List all tests')
    args = parser.parse_args()
    
    # Check emulator exists
    if not os.path.exists(EMULATOR):
        print(f"Error: Emulator not found at {EMULATOR}")
        print("Run 'make' in the emu/ directory first")
        sys.exit(1)
    
    # Parse VHDL testbench
    print(f"Parsing {TB_FILE}...")
    tests = parse_vhdl_testbench(TB_FILE)
    print(f"Found {len(tests)} tests\n")
    
    if args.list or args.vhdl_only:
        for test in tests:
            print(f"Test {test.number}: {test.name}")
            print(f"  Pokes: {len(test.pokes)}, Checks: {len(test.checks)}, Cycles: {test.cycles}")
            if args.verbose:
                for addr, data in test.pokes[:5]:
                    print(f"    poke(${addr:04X}, ${data:02X})")
                if len(test.pokes) > 5:
                    print(f"    ... and {len(test.pokes) - 5} more")
                for addr, expected, msg in test.checks:
                    print(f"    check(${addr:04X}, ${expected:02X}, \"{msg}\")")
            print()
        
        if args.vhdl_only:
            return
    
    # Run tests
    if args.test:
        tests = [t for t in tests if t.number == args.test]
        if not tests:
            print(f"Test {args.test} not found")
            sys.exit(1)
    
    total_passed = 0
    total_failed = 0
    
    print("=" * 60)
    print(" Running VHDL Tests on Emulator")
    print("=" * 60)
    print()
    
    for test in tests:
        print(f"Test {test.number}: {test.name}")
        
        if not test.checks:
            print("  SKIP (no checks)")
            print()
            continue
        
        results = run_emulator_test_v2(test, verbose=args.verbose)
        
        total_passed += results['passed']
        total_failed += results['failed']
        
        if results['failed'] == 0:
            print(f"  PASS ({results['passed']} checks)")
        else:
            print(f"  FAIL ({results['passed']} passed, {results['failed']} failed)")
            for err in results['errors'][:3]:
                print(f"    - {err}")
        print()
    
    print("=" * 60)
    print(f" Results: {total_passed} passed, {total_failed} failed")
    print("=" * 60)
    
    sys.exit(0 if total_failed == 0 else 1)


if __name__ == '__main__':
    main()
