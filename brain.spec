# -*- mode: python ; coding: utf-8 -*-

from PyInstaller.utils.hooks import collect_submodules

# uvicorn.run("src.api:app", ...) resolves that target by string at runtime,
# so PyInstaller's static import graph never sees it and never bundles
# src/api.py (or anything it imports, e.g. fastapi) unless told to explicitly.
# uvicorn itself also picks its event-loop/protocol backend dynamically, so it
# needs every submodule collected rather than a hand-picked list.
a = Analysis(
    ['src\\main.py'],
    pathex=['.'],
    binaries=[],
    datas=[],
    hiddenimports=['src.api'] + collect_submodules('uvicorn'),
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='brain',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
