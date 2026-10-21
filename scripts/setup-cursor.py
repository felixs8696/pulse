#!/usr/bin/python3
"""Package this tiny local extension without npm/vsce or network access."""
from pathlib import Path
import subprocess
import zipfile
import sys

root = Path(__file__).resolve().parent.parent
output = root / "build/pulse-router.vsix"
output.parent.mkdir(exist_ok=True)
manifest = '''<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011"><Metadata>
<Identity Language="en-US" Id="pulse-router" Version="1.1.1" Publisher="local"/>
<DisplayName>Pulse local bridge</DisplayName><Description xml:space="preserve">Open existing Cursor sessions locally.</Description>
<Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.90.0"/></Properties>
</Metadata><Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation><Dependencies/>
<Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets></PackageManifest>'''
types = '''<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="json" ContentType="application/json"/><Default Extension="js" ContentType="application/javascript"/><Default Extension="vsixmanifest" ContentType="text/xml"/></Types>'''
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    archive.writestr("extension.vsixmanifest", manifest)
    archive.writestr("[Content_Types].xml", types)
    for file in (root / "cursor-router").iterdir():
        archive.write(file, "extension/" + file.name)
if "--package-only" in sys.argv:
    print("Packaged:", output)
else:
    subprocess.run(["/Applications/Cursor.app/Contents/Resources/app/bin/cursor", "--install-extension", str(output), "--force"], check=True)
    print("Cursor bridge installed. The navigation extension activates on its first link; existing agents can stay running.")
