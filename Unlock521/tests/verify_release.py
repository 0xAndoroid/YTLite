# /// script
# dependencies = ["lief==1.0.0", "unicorn==2.1.4"]
# ///
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

import lief
from unicorn import UC_ARCH_ARM64, UC_HOOK_CODE, UC_MODE_ARM, Uc
from unicorn.arm64_const import (
    UC_ARM64_REG_LR, UC_ARM64_REG_PC, UC_ARM64_REG_SP,
    UC_ARM64_REG_X0, UC_ARM64_REG_X1, UC_ARM64_REG_X2,
)

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from patch_tweak import patch_binary

lief.logging.disable()

KEY = 0x2601000
DEFAULTS = 0x2602000
BLOCK = 0x2603000
RETURN = 0x3000000
STACK = 0x3100000


class Runtime:
    def __init__(self, data, version, value=1, ready=False, locked=False, access=False):
        self.binary = lief.MachO.parse(list(data)).at(0)
        self.vm = Uc(UC_ARCH_ARM64, UC_MODE_ARM)
        self.vm.mem_map(0, 0x4000000)
        for segment in self.binary.segments:
            if segment.file_size:
                self.vm.mem_write(segment.virtual_address, bytes(segment.content))
        for relocation in self.binary.relocations:
            if hasattr(relocation, "target"):
                self.vm.mem_write(relocation.address, struct.pack("<Q", relocation.target))
        self.imports = {}
        for index, binding in enumerate(self.binary.bindings):
            address = 0x2800000 + index * 8
            self.vm.mem_write(binding.address, struct.pack("<Q", address))
            self.imports[address] = binding.symbol.name

        # Simulate activation state; Foundation and libdispatch remain outside the emulator.
        if version == "5.2.1":
            self.vm.mem_write(0x1209C10, bytes([access, locked, ready]))
            once = 0x1209C38
        else:
            self.vm.mem_write(0x1225D10, bytes([ready, locked]))
            once = 0x1225D30
        self.vm.mem_write(once, struct.pack("<q", -1))
        self.version = version
        self.value = value
        self.access = access
        self.reads = []
        self.queued = []
        self.deferred = []
        self.vm.hook_add(UC_HOOK_CODE, self.hook)

    def return_value(self, value):
        self.vm.reg_write(UC_ARM64_REG_X0, value)
        self.vm.reg_write(UC_ARM64_REG_PC, self.vm.reg_read(UC_ARM64_REG_LR))

    def hook(self, vm, address, size, data):
        if self.version == "5.2.2" and address == 0x239C8:
            self.return_value(self.access)
            return
        name = self.imports.get(address)
        if name is None:
            return
        x0, x1, x2 = (vm.reg_read(reg) for reg in (UC_ARM64_REG_X0, UC_ARM64_REG_X1, UC_ARM64_REG_X2))
        result = x0
        if name in ("_objc_retain", "_objc_retainAutoreleasedReturnValue", "_objc_release",
                    "_objc_sync_enter", "_objc_sync_exit"):
            pass
        elif name == "_objc_msgSend":
            selector = bytes(vm.mem_read(x1, 128)).split(b"\0")[0].decode()
            if selector == "standardUserDefaults":
                result = DEFAULTS
            elif selector in ("boolForKey:", "integerForKey:"):
                assert x2 == KEY, "Preference key changed"
                self.reads.append(selector)
                result = self.value
            elif selector == "copy":
                pass
            elif selector == "addObject:":
                self.deferred.append(x2)
            else:
                raise AssertionError(f"Unexpected selector: {selector}")
        elif name == "_dispatch_async":
            assert self.imports[x0] == "__dispatch_main_q", "Hook installation left the main queue"
            captured, = struct.unpack("<Q", bytes(vm.mem_read(x1 + 32, 8)))
            self.queued.append(captured)
        else:
            raise AssertionError(f"Unexpected import: {name}")
        self.return_value(result)

    def call(self, symbol, argument):
        address = self.binary.get_symbol(symbol).export_info.address
        self.vm.reg_write(UC_ARM64_REG_SP, STACK)
        self.vm.reg_write(UC_ARM64_REG_LR, RETURN)
        self.vm.reg_write(UC_ARM64_REG_X0, argument)
        self.vm.emu_start(address, RETURN, count=10000)
        assert self.vm.reg_read(UC_ARM64_REG_PC) == RETURN, "Function did not return"
        assert self.vm.reg_read(UC_ARM64_REG_SP) == STACK, "Stack not restored"
        return self.vm.reg_read(UC_ARM64_REG_X0)


def verify(data):
    version, patched = patch_binary(data)
    for symbol in ("_ytpBool", "_ytpInt"):
        runtime = Runtime(data, version)
        assert runtime.call(symbol, KEY) == 0
        assert not runtime.reads

    for access, locked in ((False, False), (True, True)):
        for symbol, value in (("_ytpBool", 0), ("_ytpBool", 1), ("_ytpInt", 0x123456789)):
            runtime = Runtime(patched, version, value, locked=locked, access=access)
            assert runtime.call(symbol, KEY) == value
            assert len(runtime.reads) == 1

    for ready in (False, True):
        runtime = Runtime(data, version, ready=ready)
        runtime.call("_ptnRegisterBlock", BLOCK)
        assert runtime.queued == ([BLOCK] if ready else [])
        assert runtime.deferred == ([] if ready else [BLOCK])
        runtime = Runtime(patched, version, ready=ready)
        runtime.call("_ptnRegisterBlock", BLOCK)
        assert runtime.queued == [BLOCK]
        assert not runtime.deferred

    try:
        patch_binary(data[:-1])
    except ValueError:
        pass
    else:
        raise AssertionError("Modified binary accepted")
    print(f"YTLite {version}: preference values, hook dispatch, and binary validation passed")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="ytlite-test-") as directory:
        subprocess.run(["dpkg-deb", "-x", sys.argv[1], directory], check=True)
        library, = Path(directory).rglob("YTLite.dylib")
        verify(library.read_bytes())
