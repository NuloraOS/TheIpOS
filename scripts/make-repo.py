import bz2
import gzip
import hashlib
import html
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1]).resolve()
packages = subprocess.check_output(['dpkg-scanpackages', '--multiversion', '.', '/dev/null'], cwd=root)
blocks = [block for block in packages.split(b'\n\n') if block.strip()]
expected = {b'com.theipos.camera',b'com.theipos.o2camera',b'com.theipos.dock'}
found = {next(line.split(b': ',1)[1] for line in block.splitlines() if line.startswith(b'Package: ')) for block in blocks}
if found != expected or len(blocks) != 3:
    raise SystemExit('Only the two cameras and Dock may be published')
packages = b'\n\n'.join(blocks) + b'\n\n'
(root/'Packages').write_bytes(packages)
(root/'Packages.gz').write_bytes(gzip.compress(packages,mtime=0))
(root/'Packages.bz2').write_bytes(bz2.compress(packages))
release = 'Origin: Nelora\nLabel: Nelora\nSuite: stable\nVersion: 1.0\nCodename: nelora\nArchitectures: iphoneos-arm\nComponents: main\nDescription: Two cameras and Dock for iOS 12 / Chimera\n'
for label,algorithm in [('MD5Sum','md5'),('SHA1','sha1'),('SHA256','sha256'),('SHA512','sha512')]:
    release += label+':\n'
    for name in ['Packages','Packages.gz','Packages.bz2']:
        data=(root/name).read_bytes()
        release += f' {hashlib.new(algorithm,data).hexdigest()} {len(data)} {name}\n'
(root/'Release').write_text(release,encoding='utf8')
(root/'.nojekyll').touch()
links=[]
for file in sorted(root.rglob('*.deb')):
    name=subprocess.check_output(['dpkg-deb','-f',str(file),'Name'],text=True).strip()
    links.append(f'<p><a href="{file.relative_to(root).as_posix()}">{html.escape(name)} — DEB</a></p>')
(root/'index.html').write_text('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Nelora</title><style>body{max-width:760px;margin:10vh auto;padding:24px;background:#09090c;color:#eee;font:18px system-ui}a{color:#c3a3ff}</style><h1>Все приложения</h1>'+''.join(links),encoding='utf8')
print('PASS: exactly two cameras and Dock; Release includes Components')
