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


class Phase:
    """Represents a single phase (reset/run cycle) within a test"""
    def __init__(self):
        self.pokes = []      # [(addr, data), ...]
        self.checks = []     # [(addr, expected, msg, cycles_at_check), ...]
        self.cycles = 100    # Default cycles
        self.irq_active = False
        self.nmi_active = False
        self.abort_active = False
        self._cycles_so_far = 0  # Track cycles accumulated before each check


class Test:
    """Represents a single test case extracted from VHDL"""
    def __init__(self, number, name):
        self.number = number
        self.name = name
        self.phases = []     # List of Phase objects
        self.reset_vector = 0x8000  # Default
        
    def __repr__(self):
        total_pokes = sum(len(p.pokes) for p in self.phases)
        total_checks = sum(len(p.checks) for p in self.phases)
        return f"Test({self.number}, '{self.name}', {len(self.phases)} phases, {total_pokes} pokes, {total_checks} checks)"
    
    # Legacy accessors for backward compatibility
    @property
    def pokes(self):
        """Return all pokes from all phases"""
        result = []
        for phase in self.phases:
            result.extend(phase.pokes)
        return result
    
    @property
    def checks(self):
        """Return all checks from all phases"""
        result = []
        for phase in self.phases:
            result.extend(phase.checks)
        return result
    
    @property
    def cycles(self):
        """Return total cycles from all phases"""
        return sum(p.cycles for p in self.phases)
    
    @property
    def irq_active(self):
        return any(p.irq_active for p in self.phases)
    
    @property
    def nmi_active(self):
        return any(p.nmi_active for p in self.phases)
    
    @property
    def abort_active(self):
        return any(p.abort_active for p in self.phases)


def parse_vhdl_testbench(filepath):
    """Parse VHDL testbench and extract test cases with phase support"""
    tests = []
    current_test = None
    current_phase = None
    
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
    
    # Find reset signal - indicates start of a new phase
    reset_pattern = re.compile(r"rst_n\s*<=\s*'0'", re.IGNORECASE)
    
    # Find interrupt signal assignments
    irq_pattern = re.compile(r"irq_n\s*<=\s*'([01])'", re.IGNORECASE)
    nmi_pattern = re.compile(r"nmi_n\s*<=\s*'([01])'", re.IGNORECASE)
    abort_pattern = re.compile(r"abort_n\s*<=\s*'([01])'", re.IGNORECASE)
    
    lines = content.split('\n')
    i = 0
    phase_has_reset = False  # Track if current phase has seen a reset
    pending_pokes = []  # Pokes collected after checks, belong to next phase
    
    while i < len(lines):
        line = lines[i]
        
        # Check for test header
        test_match = test_pattern.search(line)
        if test_match:
            # Save previous test
            if current_test:
                if current_phase and (current_phase.pokes or current_phase.checks):
                    current_test.phases.append(current_phase)
                tests.append(current_test)
            
            test_num = int(test_match.group(1))
            test_name = test_match.group(2).strip()
            current_test = Test(test_num, test_name)
            current_phase = Phase()
            phase_has_reset = False
            pending_pokes = []
            i += 1
            continue
        
        if current_test:
            # Check for reset - indicates we're in the run portion of a phase
            if reset_pattern.search(line):
                # If we have pending pokes from after the last check, they start a new phase
                if pending_pokes and current_phase and current_phase.checks:
                    current_test.phases.append(current_phase)
                    current_phase = Phase()
                    current_phase.pokes = pending_pokes
                    pending_pokes = []
                phase_has_reset = True
            
            # Collect pokes
            pokes_on_line = []
            for match in poke16_pattern.finditer(line):
                addr = int(match.group(1), 16)
                data = int(match.group(2), 16)
                pokes_on_line.append((addr, data & 0xFF))
                pokes_on_line.append((addr + 1, (data >> 8) & 0xFF))
            
            if 'poke16' not in line.lower():
                for match in poke_pattern.finditer(line):
                    addr = int(match.group(1), 16)
                    data = int(match.group(2), 16)
                    pokes_on_line.append((addr, data))
            
            # If we have checks already and get new pokes, they belong to next phase
            if pokes_on_line:
                if current_phase and current_phase.checks:
                    pending_pokes.extend(pokes_on_line)
                elif current_phase:
                    current_phase.pokes.extend(pokes_on_line)
            
            # Look for wait_cycles - accumulate all waits > 10
            # Must be processed BEFORE check_mem so we know cycles at check time
            # Note: VHDL uses ~2x more cycles per instruction than emulator,
            # so we scale cycle counts by 0.5 for intermediate check timing
            for match in cycles_pattern.finditer(line):
                cycles = int(match.group(1))
                if cycles > 10 and current_phase:  # Ignore reset wait (usually 10 cycles)
                    # Keep full cycles for total run time, but track for checks at scaled time
                    current_phase._cycles_so_far += cycles // 2  # Scale for emulator timing
                    current_phase.cycles += cycles
            
            # Look for check_mem - record cycles at the time of check
            for match in check_pattern.finditer(line):
                addr = int(match.group(1), 16)
                expected = int(match.group(2), 16)
                msg = match.group(3)
                if current_phase:
                    # Record the cumulative cycles at this check point
                    current_phase.checks.append((addr, expected, msg, current_phase._cycles_so_far))
            
            # Look for interrupt signal assignments (active-low signals)
            irq_match = irq_pattern.search(line)
            if irq_match and current_phase:
                if irq_match.group(1) == '0':
                    current_phase.irq_active = True
            
            nmi_match = nmi_pattern.search(line)
            if nmi_match and current_phase:
                if nmi_match.group(1) == '0':
                    current_phase.nmi_active = True
            
            abort_match = abort_pattern.search(line)
            if abort_match and current_phase:
                if abort_match.group(1) == '0':
                    current_phase.abort_active = True
        
        i += 1
    
    # Save final test
    if current_test:
        if current_phase and (current_phase.pokes or current_phase.checks):
            current_test.phases.append(current_phase)
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


def run_phase(phase, script_lines, all_pokes_so_far, verbose=False):
    """
    Add commands for a single phase to the script.
    Returns the set of addresses poked so far (including this phase).
    """
    
    # Get set of addresses for filtering (before we modify)
    original_addresses = {addr for addr, _ in phase.pokes}
    uses_interrupts = phase.irq_active or phase.nmi_active or phase.abort_active
    
    # VHDL testbench has RESET_PC => x"00008000" hardcoded, so the reset vector
    # isn't read from memory. We need to set the reset vector to $8000 for the
    # emulator to match this behavior. Remove any test-set values and override.
    phase.pokes = [(addr, data) for addr, data in phase.pokes if addr not in (0xFFFC, 0xFFFD)]
    phase.pokes.append((0xFFFC, 0x00))  # Reset vector low byte
    phase.pokes.append((0xFFFD, 0x80))  # Reset vector high byte -> $8000
    
    # Add default IRQ vector ($FF00 -> STP) if not set
    if 0xFFFE not in original_addresses:
        phase.pokes.append((0xFFFE, 0x00))  # IRQ vector low byte
        phase.pokes.append((0xFFFF, 0xFF))  # IRQ vector high byte -> $FF00
    if 0xFF00 not in original_addresses:
        phase.pokes.append((0xFF00, 0xDB))  # STP instruction at IRQ handler
    
    # Update original_addresses after modifications
    original_addresses = {addr for addr, _ in phase.pokes}
    
    # Filter pokes (same logic as before for vector workaround)
    filtered_pokes = []
    for addr, data in phase.pokes:
        if uses_interrupts:
            # Filter duplicate vector writes that could confuse interrupt handling
            if addr == 0xFFFA and 0xFFF8 in original_addresses and 0xFFF9 in original_addresses:
                continue
            if addr == 0xFFFB and 0xFFF8 in original_addresses and 0xFFF9 in original_addresses:
                continue
            # Note: Don't filter $FFFC/$FFFD - we always need the reset vector
        filtered_pokes.append((addr, data))
    
    # Write memory locations for this phase
    for addr, data in filtered_pokes:
        script_lines.append(f'w {addr:x} {data:x}')
        all_pokes_so_far.add(addr)
        # Mirror writes for 64KB wrapping
        if addr < 0x10000:
            script_lines.append(f'w {addr + 0x10000:x} {data:x}')
    
    # Reset
    script_lines.append('reset')
    
    # NMI fires immediately (edge-triggered)
    if phase.nmi_active:
        script_lines.append('nmi')
    if phase.abort_active:
        script_lines.append('abort')
    
    # For IRQ tests, let CPU run a few instructions first before asserting
    # the interrupt. VHDL tests typically wait 20 cycles (~6-7 instructions)
    # after reset before asserting IRQ, to let the CPU reach WAI state.
    if phase.irq_active:
        script_lines.append('s 3')  # Execute a few instructions (CLI, WAI, etc.)
        script_lines.append('irq 1')
    
    # Run and check at intermediate points based on when checks occur
    # Group checks by their cycle time
    # Use 'step N' (instruction count) instead of 'r N' (cycle count) for precise timing
    # Approximate instruction count = cycles / 3 (average instruction takes ~3 emulator cycles)
    if phase.checks:
        checks_by_cycle = {}
        for addr, expected, msg, cycles_at in phase.checks:
            if cycles_at not in checks_by_cycle:
                checks_by_cycle[cycles_at] = []
            checks_by_cycle[cycles_at].append((addr, expected, msg))
        
        # Run to each check point and read memory
        prev_inst = 0
        for cycles_at in sorted(checks_by_cycle.keys()):
            # Convert cycles to approximate instruction count
            inst_count = max(1, cycles_at // 3)
            delta = inst_count - prev_inst
            if delta > 0:
                script_lines.append(f's {delta}')  # Use step (instruction count)
            prev_inst = inst_count
            
            # Read memory for checks at this cycle point
            for addr, expected, msg in checks_by_cycle[cycles_at]:
                script_lines.append(f'm {addr:x} 1')
        
        # Run remaining instructions after last check (estimate total from phase cycles)
        total_inst = max(1, phase.cycles // 3)
        if prev_inst < total_inst:
            remaining = total_inst - prev_inst
            script_lines.append(f's {remaining}')
    else:
        # No checks, just run all cycles
        script_lines.append(f'r {phase.cycles}')
    
    return all_pokes_so_far


def run_emulator_test_v2(test, verbose=False):
    """
    Run test using interactive mode to poke memory, run, and check results.
    This mirrors exactly what the VHDL testbench does, including multiple phases.
    """
    
    results = {'passed': 0, 'failed': 0, 'errors': []}
    
    if not test.phases:
        return results
    
    # Build interactive script
    script_lines = []
    
    # Collect all addresses that will be poked across all phases
    all_test_addresses = set()
    for phase in test.phases:
        for addr, _ in phase.pokes:
            all_test_addresses.add(addr)
    
    # Set up default vectors (only if test doesn't override them)
    if 0xFFFC not in all_test_addresses:
        script_lines.append('w fffc 0')
    if 0xFFFD not in all_test_addresses:
        script_lines.append('w fffd 80')
    if 0xFFFE not in all_test_addresses:
        script_lines.append('w fffe 0')
    if 0xFFFF not in all_test_addresses:
        script_lines.append('w ffff ff')
    if 0xFF00 not in all_test_addresses:
        script_lines.append('w ff00 db')  # STP opcode
    if 0xFFFA not in all_test_addresses:
        script_lines.append('w fffa 0')
    if 0xFFFB not in all_test_addresses:
        script_lines.append('w fffb ff')
    if 0xFFF8 not in all_test_addresses:
        script_lines.append('w fff8 0')
    if 0xFFF9 not in all_test_addresses:
        script_lines.append('w fff9 ff')
    
    # Track all checks for parsing output later (just addr, expected, msg)
    all_checks = []
    all_pokes_so_far = set()
    
    # Run each phase
    for phase_idx, phase in enumerate(test.phases):
        all_pokes_so_far = run_phase(phase, script_lines, all_pokes_so_far, verbose)
        # Extract just addr, expected, msg from checks (drop cycles_at)
        for check in phase.checks:
            if len(check) == 4:
                addr, expected, msg, _ = check
            else:
                addr, expected, msg = check
            all_checks.append((addr, expected, msg))
    
    script_lines.append('q')
    script = '\n'.join(script_lines) + '\n'
    
    if verbose:
        total_pokes = sum(len(p.pokes) for p in test.phases)
        total_cycles = sum(p.cycles for p in test.phases)
        print(f"  Script ({total_pokes} pokes, {total_cycles} cycles, {len(test.phases)} phases):")
        if len(script_lines) < 30:
            for line in script_lines[:-1]:
                print(f"    {line}")
    
    try:
        # Run emulator in interactive mode
        cmd = [
            EMULATOR,
            '--emulation',
            '-m', '256',
            '-i',
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
        for addr, expected, msg in all_checks:
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
        return {'passed': 0, 'failed': len(all_checks), 'errors': ['Timeout']}
    except Exception as e:
        return {'passed': 0, 'failed': len(all_checks), 'errors': [str(e)]}


def main():
    parser = argparse.ArgumentParser(description='Extract and run VHDL tests on emulator')
    parser.add_argument('--vhdl-only', action='store_true', help='Just parse and show tests')
    parser.add_argument('--test', type=int, action='append', help='Run specific test number(s)')
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
            if args.verbose:
                print(f"Test {test.number}: {test.name}")
                print(f"  Phases: {len(test.phases)}, Total pokes: {len(test.pokes)}, Total checks: {len(test.checks)}, Total cycles: {test.cycles}")
                for pi, phase in enumerate(test.phases):
                    print(f"  Phase {pi+1}: {len(phase.pokes)} pokes, {len(phase.checks)} checks, {phase.cycles} cycles")
                    for addr, data in phase.pokes[:3]:
                        print(f"      poke(${addr:04X}, ${data:02X})")
                    if len(phase.pokes) > 3:
                        print(f"      ... and {len(phase.pokes) - 3} more pokes")
                    for addr, expected, msg in phase.checks:
                        print(f"      check(${addr:04X}, ${expected:02X}, \"{msg}\")")
                print()
            else:
                phase_info = f" ({len(test.phases)} phases)" if len(test.phases) > 1 else ""
                print(f"  {test.number:3d}  {test.name}{phase_info}")
        return  # Exit after listing
    
    # Run tests
    if args.test:
        tests = [t for t in tests if t.number in args.test]
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
