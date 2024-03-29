{{
*****************************************
* Servo32v3 Driver v1.3                 *
* Author: Beau Schwabe                  *
* Copyright (c) 2007 Parallax           *
* See end of file for terms of use.     *
*****************************************
}}


''
''*****************************************************************
'' Control up to 8-Servos      Version3                03-08-2006 
''*****************************************************************
'' Coded by Beau Schwabe (Parallax) and Jason Dorie
''
'' This is the standard Servo32 driver modified to support a 250Hz
'' output rate for use with Quad/Hexa/Octo Copters                                             
''*****************************************************************
''
''The preferred circuit of choice is to place a 4.7K resistor on each signal input
''to the servo.  If long leads are used, place a 1000uF cap at the servo power
''connector.  Servo's seem to be happy with a 5V supply receiving a 3.3V signal.
''
''This code ONLY handles servos on pins 8-15.  If you want to support a different
''pin range, you will need to change which code sections are commented out at the
''top of the DAT section, and you will have to change the offset value in the Set
''function.  Currently, Zone2 (P8-P15) is the only zone active.  Only one zone will
''work at the 250Hz update rate. 

''---------------------------------------------------------------------------------
''DO NOT use this code with standard servos as you will fry them.  The update rate
''is 5x that of normal servos, and will cause their internals to short out. 
''---------------------------------------------------------------------------------



CON 
    _1uS = 1_000_000 /        1                                                 'Divisor for 1 uS

    ZonePeriod = 4_000                                                          '~250Hz update rate - significantly faster than typical 50Hz (this value is in uS)
    NoGlitchWindow = 2_500                                                      '2.5mS Glitch prevention window (set value larger than maximum servo width of 2mS)
                                                                                'Use at least 500uS for overhead (actual overhead about 300uS)

VAR
        long          ZoneClocks
        long          NoGlitch
        long          ServoPinDirection
        long          ServoData[8]                                              '8-15 Servo Pulse Width information

PUB AddPin(Pin)
      dira[Pin] := 1                                                            'set selected servo pin as an OUTPUT
      ServoPinDirection := dira                                                 'Read I/O state of ALL pins

PUB Start
    ZoneClocks := (clkfreq / _1uS * ZonePeriod)                                 'calculate # of clocks per ZonePeriod
    NoGlitch   := $FFFF_FFFF-(clkfreq / _1uS * NoGlitchWindow)                  'calculate # of clocks for GlitchFree servos. Problem occurs when 'cnt' value rollover is less than the servo's pulse width.                                                                                                                                                                                                                         
    cognew(@ServoStart,@ZoneClocks)                                             

PUB Set(Pin, Width)                                                             'Set Servo value
      ServoData[Pin-8] := constant(80000000 / _1uS) * Width                     'calculate # of clocks for a specific Pulse Width
    
DAT

'*********************
'* Assembly language *
'*********************
                        org
'------------------------------------------------------------------------------------------------------------------------------------------------
ServoStart              mov     Index,                  par                     'Set Index Pointer
                        rdlong  _ZoneClocks,            Index                   'Get ZoneClock value
                        add     Index,                  #4                      'Increment Index to next Pointer
                        rdlong  _NoGlitch,              Index                   'Get NoGlitch value
                        add     Index,                  #4                      'Increment Index to next Pointer
                        rdlong  _ServoPinDirection,     Index                   'Get I/O pin directions
                        add     Index,                  #32                     'Increment Index to END of Zone1 Pointer
                        mov     Zone1Index,             Index                   'Set Index Pointer for Zone1
'                        add     Index,                  #32                     'Increment Index to END of Zone2 Pointer
'                        mov     Zone2Index,             Index                   'Set Index Pointer for Zone2
'                        add     Index,                  #32                     'Increment Index to END of Zone3 Pointer
'                        mov     Zone3Index,             Index                   'Set Index Pointer for Zone3
'                        add     Index,                  #32                     'Increment Index to END of Zone4 Pointer
'                        mov     Zone4Index,             Index                   'Set Index Pointer for Zone4
                        mov     dira,                   _ServoPinDirection      'Set I/O directions
'------------------------------------------------------------------------------------------------------------------------------------------------
Zone1                   mov     ZoneIndex,              Zone1Index              'Set Index Pointer for Zone1
                        call    #ResetZone
'                        call    #ZoneCore
'Zone2                   mov     ZoneIndex,              Zone2Index              'Set Index Pointer for Zone2
                        call    #IncrementZone
                        call    #ZoneCore
'Zone3                   mov     ZoneIndex,              Zone3Index              'Set Index Pointer for Zone3
'                        call    #IncrementZone
'                        call    #ZoneCore
'Zone4                   mov     ZoneIndex,              Zone4Index              'Set Index Pointer for Zone4
'                        call    #IncrementZone
'                        call    #ZoneCore
                        jmp     #Zone1
'------------------------------------------------------------------------------------------------------------------------------------------------
ResetZone               mov     ZoneShift1,             #1
                        mov     ZoneShift2,             #2                        
                        mov     ZoneShift3,             #4
                        mov     ZoneShift4,             #8
                        mov     ZoneShift5,             #16
                        mov     ZoneShift6,             #32
                        mov     ZoneShift7,             #64
                        mov     ZoneShift8,             #128
ResetZone_RET           ret                        
'------------------------------------------------------------------------------------------------------------------------------------------------
IncrementZone           shl     ZoneShift1,             #8
                        shl     ZoneShift2,             #8                        
                        shl     ZoneShift3,             #8
                        shl     ZoneShift4,             #8
                        shl     ZoneShift5,             #8
                        shl     ZoneShift6,             #8
                        shl     ZoneShift7,             #8
                        shl     ZoneShift8,             #8
IncrementZone_RET       ret                        
'------------------------------------------------------------------------------------------------------------------------------------------------
ZoneCore                mov     ServoByte,              #0                      'Clear ServoByte
                        mov     Index,                  ZoneIndex               'Set Index Pointer for proper Zone

ZoneSync                mov     SyncPoint,              cnt                     'Create a Sync Point with the system counter
                        mov     temp,                   _NoGlitch               'Test to make sure 'cnt' value won't rollover within Servo's pulse width
                        sub     temp,                   cnt                  wc 'Subtract NoGlitch from cnt ; write result in C flag
              if_C      jmp     #ZoneSync                                       'If C flag is set get a new Sync Point, otherwise we are ok.

                        mov     LoopCounter,            #8                      'Set Loop Counter to 8 Servos for this Zone
                        movd    LoadServos,             #ServoWidth8            'Restore/Set self-modifying code on "LoadServos" line
                        movd    ServoSync,              #ServoWidth8            'Restore/Set self-modifying code on "ServoSync" line
        LoadServos      rdlong  ServoWidth8,            Index                   'Get Servo Data
        ServoSync       add     ServoWidth8,            SyncPoint               'Determine system counter location where pulse should end
                        sub     Index,                  #4                      'Decrement Index pointer to next address
                        sub     LoadServos,             d_field                 'self-modify destination pointer for "LoadServos" line
                        sub     ServoSync,              d_field                 'self-modify destination pointer for "ServoSync" line
                        djnz    LoopCounter,            #LoadServos             'Do ALL 8 servo positions for this Zone

                        mov     temp,                   _ZoneClocks             'Move _ZoneClocks into temp
                        add     temp,                   SyncPoint               'Add SyncPoint to _ZoneClocks
'----------------------------------------------Start Tight Servo code-------------------------------------------------------------
         ZoneLoop       cmpsub  ServoWidth1,            cnt           nr,wc     '(4 - clocks) compare system counter to ServoWidth ; write result in C flag
                        muxc    ServoByte,              ZoneShift1              '(4 - clocks) Set ServoByte.Bit0 to "0" or "1" depending on the value of "C"
                        cmpsub  ServoWidth2,            cnt           nr,wc     '(4 - clocks) compare system counter to ServoWidth ; write result in C flag
                        muxc    ServoByte,              ZoneShift2              '(4 - clocks) Set ServoByte.Bit1 to "0" or "1" depending on the value of "C"
                        cmpsub  ServoWidth3,            cnt           nr,wc     '(4 - clocks) compare system counter to ServoWidth ; write result in C flag
                        muxc    ServoByte,              ZoneShift3              '(4 - clocks) Set ServoByte.Bit2 to "0" or "1" depending on the value of "C"
                        cmpsub  ServoWidth4,            cnt           nr,wc     '(4 - clocks) compare system counter to ServoWidth ; write result in C flag
                        muxc    ServoByte,              ZoneShift4              '(4 - clocks) Set ServoByte.Bit3 to "0" or "1" depending on the value of "C"
                        cmpsub  ServoWidth5,            cnt           nr,wc     '(4 - clocks) compare system counter to ServoWidth ; write result in C flag
                        muxc    ServoByte,              ZoneShift5              '(4 - clocks) Set ServoByte.Bit4 to "0" or "1" depending on the value of "C"
                        cmpsub  ServoWidth6,            cnt           nr,wc     '(4 - clocks) compare system counter to ServoWidth ; write result in C flag
                        muxc    ServoByte,              ZoneShift6              '(4 - clocks) Set ServoByte.Bit5 to "0" or "1" depending on the value of "C"
                        cmpsub  ServoWidth7,            cnt           nr,wc     '(4 - clocks) compare system counter to ServoWidth ; write result in C flag
                        muxc    ServoByte,              ZoneShift7              '(4 - clocks) Set ServoByte.Bit6 to "0" or "1" depending on the value of "C"
                        cmpsub  ServoWidth8,            cnt           nr,wc     '(4 - clocks) compare system counter to ServoWidth ; write result in C flag
                        muxc    ServoByte,              ZoneShift8              '(4 - clocks) Set ServoByte.Bit7 to "0" or "1" depending on the value of "C"
                        mov     outa,                   ServoByte               '(4 - clocks) Send ServoByte to Zone Port
                        cmp     temp,                   cnt           nr,wc     '(4 - clocks) Determine if cnt has exceeded width of _ZoneClocks ; write result in C flag
                        nop                                                     '(4 - clocks) We actually had one instruction to spare                        
              if_NC     jmp     #ZoneLoop                                       '(4 - clocks) if the "C Flag" is not set stay in the current Zone
'-----------------------------------------------End Tight Servo code--------------------------------------------------------------
'                                                                        Total = 80 - clocks  @ 80MHz that's 1uS resolution
ZoneCore_RET            ret
'------------------------------------------------------------------------------------------------------------------------------------------------
d_field                 long    $0000_0200

ServoWidth1             res     1
ServoWidth2             res     1
ServoWidth3             res     1
ServoWidth4             res     1
ServoWidth5             res     1
ServoWidth6             res     1
ServoWidth7             res     1
ServoWidth8             res     1

ZoneShift1              res     1
ZoneShift2              res     1
ZoneShift3              res     1
ZoneShift4              res     1
ZoneShift5              res     1
ZoneShift6              res     1
ZoneShift7              res     1
ZoneShift8              res     1

temp                    res     1
Index                   res     1
ZoneIndex               res     1
Zone1Index              res     1
Zone2Index              res     1
Zone3Index              res     1
Zone4Index              res     1
SyncPoint               res     1

ServoByte               res     1
LoopCounter             res     1

_ZoneClocks             res     1
_NoGlitch               res     1
_ServoPinDirection      res     1

DAT
{{
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}