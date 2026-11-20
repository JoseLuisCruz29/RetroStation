# Genera un PS-X EXE mínimo (programa de prueba propio, sin herramientas externas).
# Configura la GPU (320x240, 15 bits) y rellena la pantalla con un color que
# cambia continuamente: sirve para verificar que el núcleo de PS1 ejecuta código,
# dibuja y avanza (y para probar rebobinado / save states).
param([string]$Out)

$T0 = 8; $T1 = 9; $T2 = 10; $T3 = 11; $T4 = 12; $ZERO = 0
$code = New-Object System.Collections.Generic.List[int32]
function lui($rt, $imm) { $code.Add([int32](0x3C000000 -bor ($rt -shl 16) -bor ($imm -band 0xFFFF))) }
function ori($rt, $rs, $imm) { $code.Add([int32](0x34000000 -bor ($rs -shl 21) -bor ($rt -shl 16) -bor ($imm -band 0xFFFF))) }
function andi($rt, $rs, $imm) { $code.Add([int32](0x30000000 -bor ($rs -shl 21) -bor ($rt -shl 16) -bor ($imm -band 0xFFFF))) }
function addiu($rt, $rs, $imm) { $code.Add([int32](0x24000000 -bor ($rs -shl 21) -bor ($rt -shl 16) -bor ($imm -band 0xFFFF))) }
function sw($rt, $off, $base) { $code.Add([int32](0xAC000000 -bor ($base -shl 21) -bor ($rt -shl 16) -bor ($off -band 0xFFFF))) }
function orr($rd, $rs, $rt) { $code.Add([int32](($rs -shl 21) -bor ($rt -shl 16) -bor ($rd -shl 11) -bor 0x25)) }
function sll($rd, $rt, $sa) { $code.Add([int32](($rt -shl 16) -bor ($rd -shl 11) -bor ($sa -shl 6))) }
function nop { $code.Add([int32]0) }
function bne($rs, $rt, $targetIndex) { $off = $targetIndex - ($code.Count + 1); $code.Add([int32](0x14000000 -bor ($rs -shl 21) -bor ($rt -shl 16) -bor ($off -band 0xFFFF))) }
function j($targetIndex) { $addr = 0x80010000 + 4 * $targetIndex; $code.Add([int32](0x08000000 -bor (($addr -shr 2) -band 0x3FFFFFF))) }
function li($rt, [int32]$v) { lui $rt ([int]($v -shr 16)); ori $rt $rt ([int]($v -band 0xFFFF)) }
function gp1([int32]$v) { li $T1 $v; sw $T1 4 $T0 }
function gp0([int32]$v) { li $T1 $v; sw $T1 0 $T0 }

lui $T0 0x1F80; ori $T0 $T0 0x1810        # t0 = GP0 (0x1F801810); GP1 = t0+4
gp1 0x00000000                             # reset GPU
gp1 0x08000001                             # 320x240, NTSC, 15 bits
gp1 0x05000000                             # área visible desde (0,0)
gp1 0x06C60260                             # rango horizontal estándar
gp1 0x07040010                             # rango vertical estándar
gp1 0x03000000                             # activar pantalla
gp0 0xE1000400                             # se permite dibujar en el área visible
gp0 0xE3000000                             # área de dibujo: (0,0)
gp0 0xE403BD3F                             # ... hasta (319,239)
li $T2 0                                   # contador de color
$loop = $code.Count
andi $T3 $T2 0xFF                          # rojo = contador
sll $T4 $T3 16                             # azul = contador (bits 16-23)
orr $T3 $T3 $T4
lui $T1 0x0240; orr $T1 $T1 $T3            # GP0(02h) rellenar rectángulo, verde fijo 0x40
sw $T1 0 $T0
sw $ZERO 0 $T0                             # esquina (0,0)
li $T1 0x00F00140; sw $T1 0 $T0            # tamaño 320x240
lui $T4 0x0004                             # espera (aprox. un fotograma)
$wait = $code.Count
addiu $T4 $T4 -1
bne $T4 $ZERO $wait
nop
addiu $T2 $T2 1
j $loop
nop

$body = New-Object byte[] ([math]::Ceiling($code.Count * 4 / 2048) * 2048)
for ($i = 0; $i -lt $code.Count; $i++) { [BitConverter]::GetBytes($code[$i]).CopyTo($body, $i * 4) }
$header = New-Object byte[] 2048
[Text.Encoding]::ASCII.GetBytes('PS-X EXE').CopyTo($header, 0)
[BitConverter]::GetBytes([int32]0x80010000).CopyTo($header, 0x10)   # pc0
[BitConverter]::GetBytes([int32]0x80010000).CopyTo($header, 0x18)   # t_addr
[BitConverter]::GetBytes([int32]$body.Length).CopyTo($header, 0x1C) # t_size
[BitConverter]::GetBytes([int32]0x801FFFF0).CopyTo($header, 0x30)   # s_addr (pila)
[Text.Encoding]::ASCII.GetBytes('Sony Computer Entertainment Inc. for North America area').CopyTo($header, 0x4C)
[IO.File]::WriteAllBytes($Out, $header + $body)
"PS-X EXE: $($code.Count) instrucciones, $((Get-Item $Out).Length) bytes"
