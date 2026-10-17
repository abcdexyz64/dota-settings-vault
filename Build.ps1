$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$assets=Join-Path $PSScriptRoot 'assets'
$source=[Drawing.Image]::FromFile((Join-Path $assets 'fountain.png'))
$images=@()
try {
 foreach($size in @(16,32,48,64,128,256)){
  $bitmap=New-Object Drawing.Bitmap($size,$size)
  $g=[Drawing.Graphics]::FromImage($bitmap)
  $g.InterpolationMode='HighQualityBicubic';$g.DrawImage($source,0,0,$size,$size);$g.Dispose()
  $stream=New-Object IO.MemoryStream
  $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png);$bitmap.Dispose()
  $images+=@{Size=$size;Bytes=$stream.ToArray()};$stream.Dispose()
 }
}finally{$source.Dispose()}
$file=[IO.File]::Create((Join-Path $assets 'fountain.ico'));$writer=New-Object IO.BinaryWriter($file)
try {
 $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$images.Count)
 $offset=6+16*$images.Count
 foreach($img in $images){$dim=if($img.Size -eq 256){0}else{$img.Size};$writer.Write([byte]$dim);$writer.Write([byte]$dim);$writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$img.Bytes.Length);$writer.Write([uint32]$offset);$offset+=$img.Bytes.Length}
 foreach($img in $images){$writer.Write([byte[]]$img.Bytes)}
}finally{$writer.Dispose();$file.Dispose()}
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $compiler /nologo /target:winexe /codepage:65001 /reference:System.Windows.Forms.dll ('/win32icon:'+(Join-Path $assets 'fountain.ico')) ('/out:'+(Join-Path $PSScriptRoot '泉印.exe')) (Join-Path $PSScriptRoot 'Launcher.cs')
if($LASTEXITCODE -ne 0){throw 'Launcher compilation failed'}
Write-Output 'BUILD_PASS'
