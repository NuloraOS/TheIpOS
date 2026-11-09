import bz2
import gzip
import hashlib
import html
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1]).resolve()
categories = [('icons', 'Icons'), ('camera', 'Camera'), ('utility', 'Utility'), ('wallpapers', 'Wallpapers'), ('motion-blur', 'Motion Blur')]
packages = subprocess.check_output(['dpkg-scanpackages', '--multiversion', '.', '/dev/null'], cwd=root)
# Keep the old DEB path usable without duplicating its APT record.
packages = b'\n\n'.join(block for block in packages.split(b'\n\n') if block.strip() and b'Filename: ./ios26/' not in block) + b'\n\n'
if any(('Package: ' + name).encode() not in packages for name in ['com.theipos.camera', 'com.theipos.motion', 'com.theipos.dock', 'com.theipos.glass']):
    raise SystemExit('All four compiled packages must be present before publishing')
(root / 'Packages').write_bytes(packages)
(root / 'Packages.gz').write_bytes(gzip.compress(packages, mtime=0))
(root / 'Packages.bz2').write_bytes(bz2.compress(packages))
release = 'Origin: Nulora\nLabel: Nulora\nSuite: stable\nCodename: ios\nArchitectures: iphoneos-arm\nComponents: main\nDescription: Icons, Camera, Utility, Wallpapers, Motion Blur\nSHA256:\n'
for name in ['Packages', 'Packages.gz', 'Packages.bz2']:
    data = (root / name).read_bytes()
    release += f' {hashlib.sha256(data).hexdigest()} {len(data)} {name}\n'
(root / 'Release').write_text(release, encoding='utf-8')
(root / '.nojekyll').touch()
style = 'body{margin:8vh auto;padding:24px;max-width:760px;background:#09090c;color:#eee;font:17px system-ui}h1{font-size:38px}a{color:#ffbd00;text-decoration:none}article{border:1px solid #2b2b31;border-radius:16px;padding:20px;margin:12px 0;background:#111115}p,small{color:#aaa;line-height:1.6}nav{display:flex;flex-wrap:wrap;gap:18px;margin-bottom:28px}code{overflow-wrap:anywhere}button{background:#ffbd00;border:0;border-radius:10px;padding:12px 18px;color:#000;cursor:pointer}'
def page(title, content):
    return f'<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>{html.escape(title)} · Nulora</title><style>{style}</style>{content}</html>'
cards = []
for folder, title in categories:
    directory = root / folder
    directory.mkdir(exist_ok=True)
    files = sorted(directory.glob('*.deb'))
    cards.append(f'<article><a href="{folder}/"><b>{title}</b></a><p>Пакетов: {len(files)}</p></article>')
    links = ''
    for file in files:
        name = subprocess.check_output(['dpkg-deb', '-f', str(file), 'Name'], text=True).strip()
        version = subprocess.check_output(['dpkg-deb', '-f', str(file), 'Version'], text=True).strip()
        sha = hashlib.sha256(file.read_bytes()).hexdigest()
        kind = 'camera' if folder == 'camera' else ('motion' if folder == 'motion-blur' else ('glass' if 'glass' in file.name else 'dock'))
        mirror = 'https://github.com/NuloraOS/TheIpOS/releases/download/v0.3.0/' + file.name
        links += f'<article><img src="../icons/nulora-{kind}.png" width="64" height="64" style="border-radius:15px" alt=""><h2>{html.escape(name)}</h2><p>Версия {html.escape(version)} · iPhone 5s / iOS 12 / Chimera</p><a href="{html.escape(file.name)}" download>Скачать DEB</a> · <a href="{html.escape(mirror)}">Другой сервер</a><p><small>При ошибке времени ожидания используйте другой сервер.<br>SHA-256: <code>{sha}</code></small></p></article>'
    if not links:
        links = '<p>Пакетов пока нет.</p>'
    if folder == 'icons':
        links = '<p>Иконки Nulora в одной теме.</p>' + ''.join(f'<img src="nulora-{kind}.png" width="96" height="96" style="border-radius:22px;margin:8px" alt="{kind}">' for kind in ['camera', 'motion', 'dock', 'glass'])
    (directory / 'index.html').write_text(page(title, f'<nav><a href="../">← Nulora</a></nav><h1>{title}</h1>{links}'), encoding='utf-8')
content = '<h1>Nulora</h1><p>Приложения и оформление для джейлбрейка.</p><nav>' + ''.join(f'<a href="{folder}/">{title}</a>' for folder, title in categories) + '</nav>'
content += '<p>Добавь адрес этой страницы в Sileo как репозиторий. Первые пакеты — экспериментальные сборки под iOS 12 / Chimera. Эффект motion blur не повышает частоту экрана.</p>'
content += ''.join(cards) + '<p><a href="Packages">Индекс пакетов</a> · <a href="https://github.com/NuloraOS/TheIpOS">Исходники</a></p>'
(root / 'index.html').write_text(page('Репозиторий', content), encoding='utf-8')
