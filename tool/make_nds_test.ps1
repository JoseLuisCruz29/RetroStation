# Genera un .nds mínimo (programa de prueba propio, sin herramientas externas).
# ARM9: enciende LCD y motores 2D A/B, modo de pantalla "gráficos" sin fondos
# (se ve el color de fondo de la paleta) y cambia ese color sin parar.
# ARM7: bucle infinito.
param([string]$Out)

$arm9 = New-Object System.Collections.Generic.List[int32]
$lits = New-Object System.Collections.Generic.List[int32]
$fix = @()   # (índice de instrucción, índice de literal)
function emit([int32]$w) { $arm9.Add($w) }
function ldr($rd, [int32]$value) { $script:fix += ,@($arm9.Count, $lits.Count); $lits.Add($value); emit ([int32](0xE59F0000 -bor ($rd -shl 12))) }

ldr 0 0x04000304                 # POWCNT1
ldr 1 0x0000820F                 # LCD + 2D A + 3D + geometría + 2D B + swap
emit ([int32]0xE5801000)         # str r1,[r0]
ldr 0 0x04000000                 # DISPCNT motor A
ldr 1 0x00010000                 # modo 1 (gráficos), sin fondos
emit ([int32]0xE5801000)         # str r1,[r0]
ldr 0 0x04001000                 # DISPCNT motor B
emit ([int32]0xE5801000)         # str r1,[r0]
ldr 4 0x05000000                 # color de fondo, motor A
ldr 5 0x05000400                 # color de fondo, motor B
emit ([int32]0xE3A02000)         # mov r2,#0
$loop = $arm9.Count
emit ([int32]0xE1C420B0)         # strh r2,[r4]
emit ([int32]0xE1E06002)         # mvn r6,r2
emit ([int32]0xE1C560B0)         # strh r6,[r5]
ldr 3 0x00080000                 # espera
$wait = $arm9.Count
emit ([int32]0xE2533001)         # subs r3,r3,#1
$off = (($wait - ($arm9.Count + 2)) -band 0xFFFFFF); emit ([int32](0x1A000000 -bor $off))  # bne wait
emit ([int32]0xE2822021)         # add r2,r2,#0x21
$off = (($loop - ($arm9.Count + 2)) -band 0xFFFFFF); emit ([int32](0xEA000000 -bor $off))  # b loop

$codeLen = $arm9.Count
foreach ($f in $fix) {           # LDR literal: offset = literal - (pc + 8)
  $offset = 4 * ($codeLen + $f[1]) - (4 * $f[0] + 8)
  $arm9[$f[0]] = $arm9[$f[0]] -bor $offset
}
$words9 = @($arm9) + @($lits)
$bin9 = New-Object byte[] ($words9.Count * 4)
for ($i = 0; $i -lt $words9.Count; $i++) { [BitConverter]::GetBytes([int32]$words9[$i]).CopyTo($bin9, $i * 4) }
$bin7 = [BitConverter]::GetBytes([int32]0xEAFFFFFE)   # b .

$arm9Off = 0x200; $arm7Off = 0x400
$total = $arm7Off + 0x200
$rom = New-Object byte[] $total
[Text.Encoding]::ASCII.GetBytes('RSTEST').CopyTo($rom, 0)
[Text.Encoding]::ASCII.GetBytes('####').CopyTo($rom, 0x0C)
function put32($o, [int64]$v) { [BitConverter]::GetBytes([int32]$v).CopyTo($rom, $o) }
put32 0x20 $arm9Off; put32 0x24 0x02000000; put32 0x28 0x02000000; put32 0x2C $bin9.Length
put32 0x30 $arm7Off; put32 0x34 0x037F8000; put32 0x38 0x037F8000; put32 0x3C $bin7.Length
put32 0x80 $total; put32 0x84 0x200
$bin9.CopyTo($rom, $arm9Off); $bin7.CopyTo($rom, $arm7Off)
# CRC-16 (polinomio 0xA001, inicial 0xFFFF) de 0x000..0x15D en 0x15E
$crc = 0xFFFF
for ($i = 0; $i -lt 0x15E; $i++) { $crc = $crc -bxor $rom[$i]; for ($b = 0; $b -lt 8; $b++) { if ($crc -band 1) { $crc = ($crc -shr 1) -bxor 0xA001 } else { $crc = $crc -shr 1 } } }
$rom[0x15E] = $crc -band 0xFF; $rom[0x15F] = ($crc -shr 8) -band 0xFF
[IO.File]::WriteAllBytes($Out, $rom)
"NDS: ARM9 $codeLen instrucciones + $($lits.Count) literales, CRC 0x{0:X4}" -f $crc
