"""Reject mandatory post-iOS-12 dependencies before publishing the actual app."""
import pathlib
import struct
import sys

app = pathlib.Path(sys.argv[1])
known_new = {'SwiftUI', 'SwiftUICore', 'Combine', 'CryptoKit', 'UniformTypeIdentifiers', 'RealityKit', 'DataDetection'}
checks = 0
for file in app.rglob('*'):
    if not file.is_file():
        continue
    data = file.read_bytes()
    if data[:4] != b'\xcf\xfa\xed\xfe':
        continue
    cpu, = struct.unpack_from('<I', data, 4)
    if cpu != 0x100000c:
        raise SystemExit(f'Wrong CPU: {file.name}')
    count, = struct.unpack_from('<I', data, 16)
    at = 32
    for _ in range(count):
        cmd, size = struct.unpack_from('<II', data, at)
        if size < 8 or at + size > len(data):
            raise SystemExit('Invalid Mach-O load command')
        if cmd == 0xC:  # LC_LOAD_DYLIB: unlike LC_LOAD_WEAK_DYLIB this is mandatory.
            offset, = struct.unpack_from('<I', data, at + 8)
            name = data[at + offset:at + size].split(b'\0', 1)[0].decode('utf8')
            if any(f'/{framework}.framework/' in name for framework in known_new):
                raise SystemExit(f'Mandatory post-iOS-12 dependency in {file.name}: {name}')
            if name.startswith('@rpath/') and not (app / 'Frameworks' / name[7:]).is_file():
                raise SystemExit(f'Missing embedded library: {name}')
        if cmd in (0x25, 0x32):
            minimum, = struct.unpack_from('<I', data, at + (8 if cmd == 0x25 else 12))
            if minimum > 12 << 16:
                raise SystemExit(f'Minimum OS above iOS 12: {file.name}')
        at += size
    checks += 1
if checks == 0:
    raise SystemExit('No compiled binaries')
print(f'PASS: {checks} arm64 binaries, no mandatory newer frameworks or missing embedded libraries')
