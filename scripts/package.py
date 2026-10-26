#!/usr/bin/env python3
"""Package a device build without adding signing material or device data."""
import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import zipfile

app, output = map(Path, sys.argv[1:])
info = plistlib.loads((app / "Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "com.iceorange.ifmobilehelper"
assert not (app / "embedded.mobileprovision").exists(), "Expected an unsigned build"
# A normal Xcode build retains linker debug-map paths even in Release mode.
# Remove those records before distribution; runtime/exported symbols stay intact.
subprocess.run(["xcrun", "strip", "-S", str(app / info["CFBundleExecutable"])], check=True)
version = info["CFBundleShortVersionString"]
output.mkdir(parents=True, exist_ok=True)
ipa = output / f"ifmobile-Helper-v{version}-unsigned.ipa"
with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for file in sorted(app.rglob("*")):
        if file.is_file():
            archive.write(file, Path("Payload") / app.name / file.relative_to(app))
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None
profile = output / "ifmobile-Roaming-Voice.mobileconfig"
shutil.copyfile(app / profile.name, profile)
checksums = "".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in (ipa, profile))
(output / "SHA256SUMS.txt").write_text(checksums)
print(f"Built {ipa.name} ({ipa.stat().st_size:,} bytes)")
print(checksums, end="")
