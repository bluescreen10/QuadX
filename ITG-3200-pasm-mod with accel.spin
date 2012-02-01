''
''
''     QuadRotor
'' -- Jason Dorie --               
''               
'' ITG-3200 Gyro and ADXL345 Accelerometer Module
'' Note that this code assumes an 80 MHz clock
''
'' Large swaths of the I2C code blatantly stolen from sdspiFemto by Michael Green

'' The ITG3200 returns a value of 14.375 per degree per second of rotation

CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000
  
VAR
  long PreviousTime, CurrentTime, ElapsedTime, Seconds, x0, y0, z0, t
  long Cog

  long rx, ry, rz, temp, ax, ay, az, arx, ary
    
OBJ

PUB Start( _SCL, _SDA ) : Status

  x0 := 0
  y0 := 0
  z0 := 0

  ComputeTimes

  i2cSCL := 1 << _SCL
  i2cSDA := 1 << _SDA
  Status := Cog := cognew(@Init_IDG3200, @rx) + 1
  
  FindZero
    
PUB Stop
''Stops the Cog and the PID controller
  if Cog
    cogstop(Cog~ - 1)


PUB GetTemp
  return temp

PUB GetRX
  return rx - x0

PUB GetRY
  return ry - y0

PUB GetRZ
  return rz - z0

PUB GetAX
  return ax

PUB GetAY
  return ay

PUB GetAZ
  return az

PUB GetARX
  return arx

PUB GetARY
  return ary


PRI computeTimes                                       '' Set up timing constants in assembly
                                                       '  (Done this way to avoid overflow)
  i2cDataSet := ((clkfreq / 10000) *  350) / 100000    ' Data setup time -  350ns (400KHz)
  i2cClkLow  := ((clkfreq / 10000) * 1300) / 100000    ' Clock low time  - 1300ns (400KHz)
  i2cClkHigh := ((clkfreq / 10000) *  600) / 100000    ' Clock high time -  600ns (400KHz)
  i2cPause   := clkfreq / 100000                       ' Pause between checks for operations


PRI FindZero | tc, xc, yc, zc, dr

  'wait 1/2 second for the body to stop moving
  waitcnt( constant(80_000_000 / 2) + cnt )

  'Find the zero points of the 3 axis by reading for ~1 sec and averaging the results
  xc := 0
  yc := 0
  zc := 0

  repeat 256
    xc += rx
    yc += ry
    zc += rz

    waitcnt( constant(80_000_000/192) + cnt )

  'Perform rounding
  if( xc > 0 )
    xc += 128
  elseif( xc < 0 )
    xc -= 128

  if( yc > 0 )
    yc += 128
  elseif( yc < 0 )
    yc -= 128

  if( zc > 0 )
    zc += 128
  elseif( zc < 0 )
    zc -= 128
    
  x0 := xc / 256
  y0 := yc / 256
  z0 := zc / 256
  


DAT
        org   0

Init_IDG3200

'  --------- Debugger Kernel add this at Entry (Addr 0) ---------
'   long $34FC1202,$6CE81201,$83C120B,$8BC0E0A,$E87C0E03,$8BC0E0A
'   long $EC7C0E05,$A0BC1207,$5C7C0003,$5C7C0003,$7FFC,$7FF8
'  -------------------------------------------------------------- 

        mov             p1, par                         ' Get data pointer
        mov             prX, p1                         ' Store the pointer to the rx var in HUB RAM
        add             p1, #4
        mov             prY, p1                         ' Store the pointer to the ry var in HUB RAM
        add             p1, #4
        mov             prZ, p1                         ' Store the pointer to the rz var in HUB RAM
        add             p1, #4
        mov             pT, p1                          ' Store the pointer to the temp var in HUB RAM
        add             p1, #4
        mov             paX, p1                         ' Store the pointer to the ax var in HUB RAM
        add             p1, #4
        mov             paY, p1                         ' Store the pointer to the ay var in HUB RAM
        add             p1, #4
        mov             paZ, p1                         ' Store the pointer to the az var in HUB RAM
        add             p1, #4
        mov             paRX, p1                        ' Store the pointer to the arx var in HUB RAM
        add             p1, #4
        mov             paRY, p1                        ' Store the pointer to the ary var in HUB RAM


        mov             i2cTemp,i2cPause
        add             i2cTemp,CNT                     ' Wait 10us before starting
        waitcnt         i2cTemp,#0

        call            #i2cReset        
        call            #SetConfig

        mov             loopCount, CNT
        add             loopCount, loopDelay


        'Gyro only loop timed at 21200 clocks, or 265us at 80MHz  

:loop
                        call    #ITGReadValues
                        call    #ITGComputeDrift
                        call    #ADXLReadValues
                        call    #ADXLComputeAngles

                        wrlong  iT, pT

                        subs    irX, drift
                        wrlong  irX, prX

                        subs    irY, drift
                        wrlong  irY, prY

                        subs    irZ, drift
                        wrlong  irZ, prZ

                        wrlong  iaX, paX
                        wrlong  iaY, paY
                        wrlong  iaZ, paZ

                        wrlong  iaRX, paRX
                        wrlong  iaRY, paRY
                        
                        waitcnt loopCount, loopDelay
                        jmp     #:loop        



'------------------------------------------------------------------------------
ITGReadValues
                        mov     i2cAddr, #27            ' Address of temperature register
                        'mov     i2cDevID, #%11010010    ' Device ID of the ITG3200
                        mov     i2cDevID, #%11010000    ' Device ID of the IMU3000
                        call    #StartRead              ' Tell the I2C device we're starting

                        mov     i2cMask, i2cWordReadMask                        
                        test    i2cTestCarry, #0 wc     ' Clear the carry flag to make reads auto-increment
                        call    #i2cRead                                          
                        call    #i2cRead

                        'Sign extend the 15th bit                        
                        test    i2cData, i2cWordReadMask     wc         
                        muxc    i2cData, i2cWordMask
                        mov     iT, i2cData


                        mov     i2cMask, i2cWordReadMask
                        test    i2cTestCarry, #0 wc      ' Clear the carry flag to make reads auto-increment                       
                        call    #i2cRead
                        call    #i2cRead

                        'Sign extend the 15th bit
                        test    i2cData, i2cWordReadMask     wc
                        muxc    i2cData, i2cWordMask
                        mov     irX, i2cData


                        mov     i2cMask, i2cWordReadMask
                        test    i2cTestCarry, #0 wc      ' Clear the carry flag to make reads auto-increment                       
                        call    #i2cRead
                        call    #i2cRead

                        'Sign extend the 15th bit
                        test    i2cData, i2cWordReadMask     wc
                        muxc    i2cData, i2cWordMask
                        mov     irY, i2cData


                        mov     i2cMask, i2cWordReadMask
                        test    i2cTestCarry, #0 wc      ' Clear the carry flag to make reads auto-increment                       
                        call    #i2cRead
                        test    i2cTestCarry, #1 wc      ' Set the carry flag to tell it we're done
                        call    #i2cRead

                        'Sign extend the 15th bit
                        test    i2cData, i2cWordReadMask     wc
                        muxc    i2cData, i2cWordMask
                        mov     irZ, i2cData

                        call    #i2cStop                        

ITGReadValues_Ret       ret




'------------------------------------------------------------------------------
                        ' Compute drift - for my gyro
                        '(Temp + 15000) / 100 = drift

'------------------------------------------------------------------------------
ITGComputeDrift
                        mov     drift, iT               ' Start with the temperature reading
                        add     drift, tempOffset       ' Offset it by 15,000

                        ' divide drift by 100                        

                        mov     divisor, #100
                        mov     dividend, drift
                        test    dividend, i2cWordReadMask    wc

                        muxc    signbit, #1             ' record the sign of the original value
                        abs     dividend, dividend

                        mov     divCounter, #10     
                        shl     divisor, divCounter
                        mov     resultShifted, #1
                        shl     resultShifted, divCounter

                        add     divCounter, #1
                        mov     drift, #0

:divLoop                        
                        cmp     dividend, divisor   wc
              if_nc     add     drift, resultShifted
              if_nc     sub     dividend, divisor
                        shr     resultShifted, #1
                        shr     divisor, #1     
                        djnz    divCounter, #:divLoop

                        test    signbit, #1     wc
                        negc    drift, drift
                        
                        
ITGComputeDrift_Ret     ret



'------------------------------------------------------------------------------
ADXLReadValues
                        mov     i2cAddr, #$32           ' Address of x register
                        mov     i2cDevID, #%10100110    ' Device ID of the ADXL345 
                        call    #StartRead              ' Tell the I2C device we're starting

                        mov     i2cMask, #%10000000
                        test    i2cTestCarry, #0 wc     ' Clear the carry flag to make reads auto-increment        
                        call    #i2cRead
                        rol     i2cMask, #16            ' This device reads low/high byte                                          
                        call    #i2cRead

                        'Sign extend the 15th bit
                        test    i2cData, i2cWordReadMask     wc
                        muxc    i2cData, i2cWordMask
                        mov     iaX, i2cData
                        neg     iaX, iaX                'For IMU3000 ADXL orientation


                        mov     i2cMask, #%10000000
                        test    i2cTestCarry, #0 wc      ' Clear the carry flag to make reads auto-increment                       
                        call    #i2cRead
                        rol     i2cMask, #16            ' This device reads low/high byte                                          
                        call    #i2cRead

                        'Sign extend the 15th bit
                        test    i2cData, i2cWordReadMask     wc   
                        muxc    i2cData, i2cWordMask
                        mov     iaY, i2cData
                        neg     iaY, iaY                'For IMU3000 ADXL orientation     

                        mov     i2cMask, #%10000000
                        test    i2cTestCarry, #0 wc      ' Clear the carry flag to make reads auto-increment
                        call    #i2cRead
                        rol     i2cMask, #16             ' This device reads low/high byte
                        test    i2cTestCarry, #1 wc      ' Set the carry flag to tell it we're done                                                                  
                        call    #i2cRead

                        'Sign extend the 15th bit
                        test    i2cData, i2cWordReadMask     wc
                        muxc    i2cData, i2cWordMask
                        mov     iaZ, i2cData

                        call    #i2cStop

ADXLReadValues_Ret      ret



'------------------------------------------------------------------------------
ADXLComputeAngles
                        mov     cx, iaZ
                        mov     cy, iaX
                        call    #cordic
                        mov     iaRX, ca

                        mov     cx, iaZ
                        mov     cy, iaY
                        call    #cordic
                        mov     iaRY, ca

ADXLComputeAngles_ret
                        ret

        
'------------------------------------------------------------------------------
SetConfig
:ITGSetConfig           'mov     i2cDevID, #%11010010     'Device ID for the ITG3200
                        mov     i2cDevID, #%11010000     'Device ID for the IMU3000   
                        mov     i2cAddr, #22
                        mov     i2cValue, #$18+2         'DLPF_FS (DLPF_CFG = 2, FS_SEL = 3) = 1Khz sample, 98Hz lowpass
                        call    #i2cWriteRegisterByte

                        mov     i2cAddr, #21
                        mov     i2cValue, #4             'SMPLRT_DIV = 4(+1) = 1KHz / 4 = 200Hz sample rate
                        call    #i2cWriteRegisterByte

                        mov     i2cAddr, #62
                        mov     i2cValue, #1             'CLK_SEL = 1 (PLL + X Osc)
                        call    #i2cWriteRegisterByte


:ADXLSetConfig          mov     i2cDevID, #%10100110    'Device ID for the ADXL345
                        mov     i2cAddr, #$31
                        mov     i2cValue, #%1001        'Set full range mode, LSB justify, 4g range
                        call    #i2cWriteRegisterByte

                        mov     i2cAddr, #$2B
                        mov     i2cValue, #%1011        'Set sample rate to 200 sps
                        call    #i2cWriteRegisterByte

                        mov     i2cAddr, #$2D
                        mov     i2cValue, #%1000        'Enable measurement mode                        
                        call    #i2cWriteRegisterByte
SetConfig_Ret           
                        ret        





'------------------------------------------------------------------------------
StartRead
                        call    #i2cStart
                        mov     i2cData, i2cDevID
                        mov     i2cMask, #%10000000
                        call    #i2cWrite

                        mov     i2cData, i2cAddr
                        mov     i2cMask,#%10000000
                        call    #i2cWrite

                        call    #i2cStart
                        mov     i2cData, i2cDevID
                        or      i2cData, #1
                        mov     i2cMask, #%10000000
                        call    #i2cWrite
                                                
StartRead_Ret           ret        




'------------------------------------------------------------------------------
i2cWriteRegisterByte
                        call    #i2cStart
                        mov     i2cData, i2cDevID
                        mov     i2cMask,#%10000000
                        call    #i2cWrite

                        mov     i2cTime,i2cClkLow
                        add     i2cTime,cnt             ' Allow for minimum SCL low
                        waitcnt i2cTime, #0

                        mov     i2cData, i2cAddr
                        mov     i2cMask,#%10000000
                        call    #i2cWrite

                        mov     i2cTime,i2cClkLow
                        add     i2cTime,cnt             ' Allow for minimum SCL low
                        waitcnt i2cTime, #0

                        mov     i2cData, i2cValue
                        mov     i2cMask,#%10000000
                        call    #i2cWrite

                        call    #i2cStop                                                                         

i2cWriteRegisterByte_Ret
                        ret



'------------------------------------------------------------------------------
'' Low level I2C routines.  These are designed to work either with a standard I2C bus
'' (with pullups on both SCL and SDA) or the Propellor Demo Board (with a pullup only
'' on SDA).  Timing can be set by the caller to 100KHz or 400KHz.


'------------------------------------------------------------------------------
'' Do I2C Reset Sequence.  Clock up to 9 cycles.  Look for SDA high while SCL
'' is high.  Device should respond to next Start Sequence.  Leave SCL high.

i2cReset                andn    dira,i2cSDA             ' Pullup drive SDA high
                        mov     i2cBitCnt,#9            ' Number of clock cycles
                        mov     i2cTime,i2cClkLow
                        add     i2cTime,cnt             ' Allow for minimum SCL low
:i2cResetClk            andn    outa,i2cSCL             ' Active drive SCL low
                        or      dira,i2cSCL            
                        waitcnt i2cTime,i2cClkHigh
                        or      outa,i2cSCL             ' Active drive SCL high
                        or      dira,i2cSCL
                        andn    dira,i2cSCL             ' Pullup drive SCL high
                        waitcnt i2cTime,i2cClkLow       ' Allow minimum SCL high
                        test    i2cSDA,ina         wz   ' Stop if SDA is high
              if_z      djnz    i2cBitCnt,#:i2cResetClk ' Stop after 9 cycles
i2cReset_ret            ret                             ' Should be ready for Start      


'------------------------------------------------------------------------------
'' Do I2C Start Sequence.  This assumes that SDA is a floating input and
'' SCL is also floating, but may have to be actively driven high and low.
'' The start sequence is where SDA goes from HIGH to LOW while SCL is HIGH.

i2cStart
                        or      outa,i2cSCL             ' Active drive SCL high
                        or      dira,i2cSCL
                        or      outa,i2cSDA             ' Active drive SDA high
                        or      dira,i2cSDA
                        
                        mov     i2cTime,i2cClkHigh
                        add     i2cTime,cnt             ' Allow for bus free time
                        waitcnt i2cTime,i2cClkLow

                        andn    outa,i2cSDA             ' Active drive SDA low
                        waitcnt i2cTime,#0

                        andn    outa,i2cSCL             ' Active drive SCL low
i2cStart_ret            ret                             


'------------------------------------------------------------------------------
'' Do I2C Stop Sequence.  This assumes that SCL is low and SDA is indeterminant.
'' The stop sequence is where SDA goes from LOW to HIGH while SCL is HIGH.
'' i2cStart must have been called prior to calling this routine for initialization.
'' The state of the (c) flag is maintained so a write error can be reported.

i2cStop
                        or      outa,i2cSCL             ' Active drive SCL high

                        mov     i2cTime,i2cClkHigh
                        add     i2cTime,cnt             ' Wait for minimum clock low
                        waitcnt i2cTime,i2cClkLow

                        or      outa,i2cSDA             ' Active drive SDA high
                        waitcnt i2cTime,i2cClkLow
                        
                        andn    dira,i2cSCL             ' Pullup drive SCL high
                        waitcnt i2cTime,i2cClkLow       ' Wait for minimum setup time

                        andn    dira,i2cSDA             ' Pullup drive SDA high
                        waitcnt i2cTime,#0              ' Allow for bus free time

i2cStop_ret             ret


'------------------------------------------------------------------------------
'' Write I2C data.  This assumes that i2cStart has been called and that SCL is low,
'' SDA is indeterminant. The (c) flag will be set on exit from ACK/NAK with ACK == false
'' and NAK == true. Bytes are handled in "little-endian" order so these routines can be
'' used with words or longs although the bits are in msb..lsb order.

i2cWrite                mov     i2cBitCnt,#8
                        mov     i2cTime,i2cClkLow
                        add     i2cTime,cnt             ' Wait for minimum SCL low
:i2cWriteBit            waitcnt i2cTime,i2cDataSet

                        test    i2cData,i2cMask    wz
              if_z      or      dira,i2cSDA             ' Copy data bit to SDA
              if_nz     andn    dira,i2cSDA
                        waitcnt i2cTime,i2cClkHigh      ' Wait for minimum setup time
                        or      outa,i2cSCL             ' Active drive SCL high

                        waitcnt i2cTime,i2cClkLow
                        
                        andn    outa,i2cSCL             ' Active drive SCL low
                        
                        ror     i2cMask,#1              ' Go do next bit if not done
                        djnz    i2cBitCnt,#:i2cWriteBit
                        
                        andn    dira,i2cSDA             ' Switch SDA to input and
                        waitcnt i2cTime,i2cClkHigh      '  wait for minimum SCL low
                        
                        or      outa,i2cSCL             ' Active drive SCL high

                        waitcnt i2cTime,i2cClkLow       ' Wait for minimum high time
                        
                        test    i2cSDA,ina         wc   ' Sample SDA (ACK/NAK) then
                        andn    outa,i2cSCL             '  active drive SCL low
                        andn    outa,i2cSDA             '  active drive SDA low
                        or      dira,i2cSDA             ' Leave SDA low
                        rol     i2cMask,#16             ' Prepare for multibyte write
                        
                        waitcnt i2cTime,#0              ' Wait for minimum low time
                        
i2cWrite_ret            ret


'------------------------------------------------------------------------------
'' Read I2C data.  This assumes that i2cStart has been called and that SCL is low,
'' SDA is indeterminant.  ACK/NAK will be copied from the (c) flag on entry with
'' ACK == low and NAK == high.  Bytes are handled in "little-endian" order so these
'' routines can be used with words or longs although the bits are in msb..lsb order.

i2cRead                 mov     i2cBitCnt,#8
                        andn    dira,i2cSDA             ' Make sure SDA is set to input
                        
                        mov     i2cTime,i2cClkLow
                        add     i2cTime,cnt             ' Wait for minimum SCL low
:i2cReadBit             waitcnt i2cTime,i2cClkHigh

                        or      outa,i2cSCL             ' Active drive SCL high
                        waitcnt i2cTime,i2cClkLow       ' Wait for minimum clock high
                        
                        test    i2cSDA,ina         wz   ' Sample SDA for data bits
                        andn    outa,i2cSCL             ' Active drive SCL low

              if_nz     or      i2cData,i2cMask         ' Accumulate data bits
              if_z      andn    i2cData,i2cMask
                        ror     i2cMask,#1              ' Shift the bit mask and
                        djnz    i2cBitCnt,#:i2cReadBit  '  continue until done
                        
                        waitcnt i2cTime,i2cDataSet      ' Wait for end of SCL low

              if_c      or      outa,i2cSDA             ' Copy the ACK/NAK bit to SDA
              if_nc     andn    outa,i2cSDA
                        or      dira,i2cSDA             ' Make sure SDA is set to output

                        waitcnt i2cTime,i2cClkHigh      ' Wait for minimum setup time
                        
                        or      outa,i2cSCL             ' Active drive SCL high
                        waitcnt i2cTime,i2cClkLow       ' Wait for minimum clock high
                        
                        andn    outa,i2cSCL             ' Active drive SCL low
                        andn    outa,i2cSDA             ' Leave SDA low

                        waitcnt i2cTime,#0              ' Wait for minimum low time

i2cRead_ret             ret


'------------------------------------------------------------------------------
'' Perform CORDIC cartesian-to-polar conversion

''Input = cx(x) and cy(x)
''Output = cx(ro) and ca(theta)

cordic                  abs       cx,cx           wc 
              if_c      neg       cy,cy             
                        mov       ca,#0             
                        rcr       ca,#1
                         
                        movs      :lookup,#cordicTable
                        mov       t1,#0
                        mov       t2,#20
                         
:loop                   mov       dx,cy           wc
                        sar       dx,t1
                        mov       dy,cx
                        sar       dy,t1
                        sumc      cx,dx
                        sumnc     cy,dy
:lookup                 sumc      ca,cordicTable
                         
                        add       :lookup,#1
                        add       t1,#1
                        djnz      t2,#:loop
                        shr       ca, #16
              
cordic_ret              ret


cordicTable             long    $20000000
                        long    $12E4051E
                        long    $09FB385B
                        long    $051111D4
                        long    $028B0D43
                        long    $0145D7E1
                        long    $00A2F61E
                        long    $00517C55
                        long    $0028BE53
                        long    $00145F2F
                        long    $000A2F98
                        long    $000517CC
                        long    $00028BE6
                        long    $000145F3
                        long    $0000A2FA
                        long    $0000517D
                        long    $000028BE
                        long    $0000145F
                        long    $00000A30
                        long    $00000518
                                    
dx                      long    0
dy                      long    0
cx                      long    0
cy                      long    0
ca                      long    0
t1                      long    0
t2                      long    0
              


'' Variables for the gyro routines

p1                      long    0
pT                      long    0                       ' Pointer to Temperature in hub ram
prX                     long    0                       ' Pointer to X rotation in hub ram
prY                     long    0                       ' Pointer to Y rotation in hub ram
prZ                     long    0                       ' Pointer to Z rotation in hub ram
paX                     long    0                       ' Pointer to X accel in hub ram
paY                     long    0                       ' Pointer to Y accel in hub ram
paZ                     long    0                       ' Pointer to Z accel in hub ram
paRX                    long    0                       ' Pointer to X accel angle in hub ram
paRY                    long    0                       ' Pointer to Y accel angle in hub ram

iT                      long    0                       ' Interim temperature value
irX                     long    0                       ' Interim rX value
irY                     long    0                       ' Interim rY value - These values are temp storage before drift compensation
irZ                     long    0                       ' Interim rZ value

iaX                     long    0                       ' Interim aX value
iaY                     long    0                       ' Interim aY value
iaZ                     long    0                       ' Interim aZ value
iaRX                    long    0                       ' Interim aX value
iaRY                    long    0                       ' Interim aY value
                                                                  
i2cWordReadMask         long    %10000000_00000000
i2cWordMask             long    $ffff0000
loopDelay               long    80_000_000 / 200
loopCount               long    0

'' Variables for dealing with drift / division
tempOffset              long    15000
drift                   long    0
divisor                 long    0
dividend                long    0
resultShifted           long    0
signbit                 long    0
divCounter              long    0


'' Variables for i2c routines
    
i2cTemp                 long    0
i2cCount                long    0
i2cValue                long    0
i2cDevID                long    0
i2cAddr                 long    0
i2cDataSet              long    0                       ' Minumum data setup time (ticks)
i2cClkLow               long    0                       ' Minimum clock low time (ticks)
i2cClkHigh              long    0                       ' Minimum clock high time (ticks)
i2cPause                long    0                       ' Pause before re-fetching next operation
i2cTestCarry            long    1                       ' Used for setting the carry flag

     
'' Local variables for low level I2C routines

i2cSCL                  long    0                       ' Bit mask for SCL
i2cSDA                  long    0                       ' Bit mask for SDA
i2cTime                 long    0                       ' Used for timekeeping
i2cData                 long    0                       ' Data to be transmitted / received
i2cMask                 long    0                       ' Bit mask for bit to be tx / rx
i2cBitCnt               long    0                       ' Number of bits to tx / rx


        FIT   496

        