import bz2
import gzip
import hashlib
import html
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1]).resolve()
categories = [('icons', 'Icons'), ('camera', 'Camera'), ('utility', 'Utility'), ('wallpapers', 'Wallpapers'), ('ios26', 'iOS 26')]
packages = subprocess.check_output(['dpkg-scanpackages', '--multiversion', '.', '/dev/null'], cwd=root)
if b'Package: com.theipos.camera' not in packages or b'Package: com.theipos.motion' not in packages:
    raise SystemExit('Both compiled packages must be present before publishing')
(root / 'Packages').write_bytes(packages)
(root / 'Packages.gz').write_bytes(gzip.compress(packages, mtime=0))
(root / 'Packages.bz2').write_bytes(bz2.compress(packages))
release = 'Origin: TheIpOS\nLabel: TheIpOS\nSuite: stable\nCodename: ios\nArchitectures: iphoneos-arm\nComponents: main\nDescription: Icons, Camera, Utility, Wallpapers, iOS 26\nSHA256:\n'
for name in ['Packages', 'Packages.gz', 'Packages.bz2']:
    data = (root / name).read_bytes()
    release += f' {hashlib.sha256(data).hexdigest()} {len(data)} {name}\n'
(root / 'Release').write_text(release, encoding='utf-8')
(root / '.nojekyll').touch()
style = 'body{margin:8vh auto;padding:24px;max-width:760px;background:#09090c;color:#eee;font:17px system-ui}h1{font-size:38px}a{color:#ffbd00;text-decoration:none}article{border:1px solid #2b2b31;border-radius:16px;padding:20px;margin:12px 0;background:#111115}p,small{color:#aaa;line-height:1.6}nav{display:flex;flex-wrap:wrap;gap:18px;margin-bottom:28px}code{overflow-wrap:anywhere}button{background:#ffbd00;border:0;border-radius:10px;padding:12px 18px;color:#000;cursor:pointer}'
def page(title, content):
    return f'<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>{html.escape(title)} · TheIpOS</title><style>{style}</style>{content}</html>'
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
        links += f'<article><h2>{html.escape(name)}</h2><p>Версия {html.escape(version)} · iPhone 5s / iOS 12 / Chimera</p><a href="{html.escape(file.name)}">Скачать DEB</a><p><small>SHA-256: <code>{sha}</code></small></p></article>'
    if not links:
        links = '<p>Пакетов пока нет.</p>'
    (directory / 'index.html').write_text(page(title, f'<nav><a href="../">← TheIpOS</a></nav><h1>{title}</h1>{links}'), encoding='utf-8')
content = '<h1>TheIpOS</h1><p>Приложения и оформление для джейлбрейка.</p><nav>' + ''.join(f'<a href="{folder}/">{title}</a>' for folder, title in categories) + '</nav>'
content += '<p>Добавь адрес этой страницы в Sileo как репозиторий. Первые пакеты — экспериментальные сборки под iOS 12 / Chimera. Эффект motion blur не повышает частоту экрана.</p>'
content += ''.join(cards) + '<p><a href="Packages">Индекс пакетов</a> · <a href="https://github.com/koziavkamurz-wq/TheIpOS">Исходники</a></p>'
(root / 'index.html').write_text(page('Репозиторий', content), encoding='utf-8')
