{
 ************************************************************************************************************
 *                                                                                                          *
 *  AUTO-RECOVER NOTICE: This file was automatically recovered from an earlier Propeller Tool session.      *
 *                                                                                                          *
 *  ORIGINAL FOLDER:     C:\Users\Nani\Dropbox\UAV\Elev8\QuadX\                                             *
 *  TIME AUTO-SAVED:     18 hours, 11 minutes ago (23/01/2012 20:45:25)                                     *
 *                                                                                                          *
 *  OPTIONS:             1)  RESTORE THIS FILE by deleting these comments and selecting File -> Save.       *
 *                           The existing file in the original folder will be replaced by this one.         *
 *                                                                                                          *
 *                           -- OR --                                                                       *
 *                                                                                                          *
 *                       2)  IGNORE THIS FILE by closing it without saving.                                 *
 *                           This file will be discarded and the original will be left intact.              *
 *                                                                                                          *
 ************************************************************************************************************
.}
''
''
''  QuadRotor - Full Stability
''     -- By Jason Dorie --               
''               
''
'' This code assumes:
'' - an R/C receiver connected to pins 0 - 3
'' - an ITG-3200 with pullups connected to pins 16 & 17
'' - four electronic speed controls (ESCs) connected to pins 8 - 11
'' - a serial interface (PropPlug) on pins 30 & 31
''
'' Other configurations are certainly possible, but will require changes to the code
''
'' Most pin assignments can be easily altered in the Main function below, with the exception
'' of the ESCs - The Servo8Fast code has been altered to support only a single bank of 8 outputs
'' at very high speed.  The current bank of 8 is hard-coded to P8-P15, however it can be changed
'' by adjusting which segments are commented out near the top of the DAT section.    




CON
  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000

  '' Motor pins for '+' shaped frame config
  OUT_F  = 0                    ' Front ESC
  OUT_R  = 1                    ' Right ESC
  OUT_B  = 2                    ' Back ESC
  OUT_L  = 3                    ' Left ESC

  '' Motor pins for 'X' shaped frame config
  OUT_FL = 0                    ' Front Left ESC                       
  OUT_FR = 1                    ' Front Right ESC
  OUT_BR = 2                    ' Back Left ESC                        
  OUT_BL = 3                    ' Back Right ESC



OBJ
  'Gyro  : "ITG-3200-pasm.spin"                          ' 1 cog
  Gyro  : "ITG-3200-pasm-mod-imu3000-adxl.spin"                          ' 1 cog              
  RC    : "RC_Receiver_4.spin"                          ' 1 cog                       
  ESC   : "Servo8Fast.spin"                             ' 1 cog
  Dbg   : "FullDuplexSerial.spin"

  RollPID   : "IntPID-scaled.spin"
  PitchPID  : "IntPID-scaled.spin"
  YawPID    : "IntPID-scaled.spin"

  Eeprom    : "Basic_I2C_Driver.spin"


VAR
  long Output[4]                                        ' Temp output flight controls array, copied into 'servo' when finished                        
  long counter
  long Thro, Aile, Elev, Rudd
  long iAile, iElev, iRudd
  long Roll, Pitch, Yaw
  long DesiredRoll, DesiredPitch, DesiredYaw
  long RollOut, PitchOut, YawOut
  long ThroMix
  long LastTime, CurTime

  long Gx, Gy, Gz                                       ' Gyro readings (instant)
  long Ax, Ay, Az                                       ' Accel readings (instant)
  long iGx, iGy, iGz                                    ' Gyro readings (integrated)


PUB Main
 
  'Dbg.Start( 31, 30, 0, 115200 )
  Dbg.Start( 25, 24, 0, 115200 )          
  'dbg.str(string("hello"))
  Gyro.Start( 16, 17 )


  ' Initialize servo values to all neutral (zero for throttles)
  ' Delay values of 1500 = center, 1000 = min, 2000 = max

  if( ThrottleStartupTime == 0 )
    Output[0] := 1000    
    Output[1] := 1000                                   ' motors off    
    Output[2] := 1000    
    Output[3] := 1000
  else
    Output[0] := 2000    
    Output[1] := 2000                     ' motors to full throttle on startup    
    Output[2] := 2000    
    Output[3] := 2000


  'Start the servo driver cog
  ESC.AddPin(8)
  ESC.AddPin(9)
  ESC.AddPin(10)
  ESC.AddPin(11)  
  ESC.Set(  8, Output[0] )
  ESC.Set(  9, Output[1] )
  ESC.Set( 10, Output[2] )
  ESC.Set( 11, Output[3] )
  ESC.Start


  'Motor startup max throttle setting, if specified
  counter := (ThrottleStartupTime * 80_000 )            'Convert value to milliseconds
  if( counter => 400 )
    waitcnt( counter + cnt )

    Output[0] := 1000    
    Output[1] := 1000                                   ' motors off    
    Output[2] := 1000    
    Output[3] := 1000
    
    ESC.Set(  8, Output[0] )
    ESC.Set(  9, Output[1] )
    ESC.Set( 10, Output[2] )
    ESC.Set( 11, Output[3] )
     

  'Initialize the RC input object
  RC.setpins( %1111 )           'Input pins are P0 - P3
  RC.start  

  'These numbers are scaled by 2^32 - the PID code internally divides the result by 2^32 on output
  'The shifts in the Init calls are just to allow the use of more human-readable values.

  RollPID.Init(    PitchRoll_PGain,  PitchRoll_IGain,  PitchRoll_DGain )
  PitchPID.Init(   PitchRoll_PGain,  PitchRoll_IGain,  PitchRoll_DGain )
  YawPID.Init(     Yaw_PGain,        Yaw_IGain,        Yaw_DGain )                    

  RollPID.SetD2Gain(  PitchRoll_D2Gain )
  PitchPID.SetD2Gain( PitchRoll_D2Gain )
  YawPID.SetD2Gain(   Yaw_D2Gain )


  'Should probably wait for the gyro to finish startup here, but it takes a while
  'for the ESCs to initialize anyway...

  'repeat until( Gyro.IsReady == 1 )

  FlightLoop



PUB FlightLoop

  counter := 0
  LastTime := cnt

  Roll := Pitch := Yaw := 0
  DesiredRoll := DesiredPitch := DesiredYaw := 0

  repeat

    if( Dbg.rxCheck == $AA )
      DoConfig
      LastTime := cnt           'Reset the loop wait counter or we'll be waiting a while
     
  
    Thro := RC.getrc(0)         'modificacion de los canales aile y elev
    Elev := RC.getrc(1)
    Aile := RC.getrc(2)
    Rudd := RC.getrc(3)
    'Aile := 0                   'isolated receiver test
    'Elev := 0
    'Rudd := 0
    iAile += Aile
    iElev += Elev
    iRudd += Rudd
    'iAile := Aile
    'iElev := Elev
    'iRudd := Rudd

    if( GyroOrientation == 0 )
      Gx := -Gyro.GetRX          ' Gyro is mounted with X = left/right, Y = front/back
      Gy := Gyro.GetRY
      Gz := Gyro.GetRZ
    elseif( GyroOrientation == 1 )
      Gy := Gyro.GetRX           ' Gyro is mounted with X = front/back, Y = left/right (90-degrees counter clockwise)
      Gx := -Gyro.GetRY           'Cambio de signo para el IMU3000
      Gz := Gyro.GetRZ
    else '( GyroOrientation == 2 )
      Gy := -Gyro.GetRX          ' Gyro is mounted with X = front/back, Y = left/right (90-degrees clockwise)
      Gx := -Gyro.GetRY
      Gz := Gyro.GetRZ

    Ay := -Gyro.GetAX           ' Gyro is mounted with X = front/back, Y = left/right (90-degrees counter clockwise)
    Ax := -Gyro.GetAY           'Cambio de signo para el IMU3000
    Az := Gyro.GetAZ
    


    'I might need to include scale factors for gyro rate here.  Mine is 14.375 lsb's per/dec/sec
    'with a maximum rate of 2000 deg/sec.  Others may need to be scaled up / down to fall into the
    'same control range.  Using (GVal << 8) ** ScaleFactor should allow enough range...  maybe?
    if ( Gx > 10 or Gx < -10 )   
      iGx += Gx
    if ( Gy > 10 or Gy < -10 )
      iGy += Gy
    if ( Gz > 10 or Gz < -10 )
      iGz += Gz
    'iGx := Gx
    'iGy := Gy
    'iGz := Gz

    'Zero all targets when throttle is off - makes for more stable liftoff
    if( Thro < -200)          'Modifique el limite hasta tanto no configuremos bien el Tx
      iGx := iAile := 0
      iGy := iElev := 0
      iGz := iRudd := 0
    'iGx := iAile := 0
    'iGy := iElev := 0
    'iGz := iRudd := 0       'for eliminate any drift to set de roll/pitch PID gains
    DesiredRoll := (iAile << 4) ** PitchRollControlScale 
    DesiredPitch := (iElev << 4) ** PitchRollControlScale
    DesiredYaw := (iRudd << 4) ** YawControlScale



    RollOut := RollPID.Calculate( DesiredRoll , iGx )    
    PitchOut := PitchPID.Calculate( DesiredPitch , iGy )    
    YawOut := YawPID.Calculate( DesiredYaw , iGz )    


    ThroMix := (Thro + 400) ~> 2                        ' Approx 0 - 256
    ThroMix <#= 64                                      ' Above 1/4 throttle, clamp it to 64
    ThroMix #>= 0

    'add 1500 to all Output values to make them 'servo friendly' again
    Thro += 1500


    if( FrameConfiguration == 0 )
      ' + configuration
      Output[OUT_F] := Thro + ((-PitchOut + YawOut) * ThroMix) ~> 6                          
      Output[OUT_R] := Thro + (( RollOut  - YawOut) * ThroMix) ~> 6  
      Output[OUT_B] := Thro + (( PitchOut + YawOut) * ThroMix) ~> 6
      Output[OUT_L] := Thro + ((-RollOut  - YawOut) * ThroMix) ~> 6
       
    else
    ' X configuration     Pitch = Y Roll =X 
      Output[OUT_FL] := Thro + (( PitchOut + RollOut - YawOut) * ThroMix) ~> 6                          
      Output[OUT_FR] := Thro + (( -PitchOut + RollOut + YawOut) * ThroMix) ~> 6  
      Output[OUT_BL] := Thro + (( PitchOut - RollOut + YawOut) * ThroMix) ~> 6
      Output[OUT_BR] := Thro + (( -PitchOut - RollOut - YawOut) * ThroMix) ~> 6
    '' X configuration
      'Output[OUT_FL] := Thro + ((-PitchOut - RollOut - YawOut) * ThroMix) ~> 6                          
     ' Output[OUT_FR] := Thro + ((-PitchOut + RollOut + YawOut) * ThroMix) ~> 6  
     ' Output[OUT_BL] := Thro + (( PitchOut - RollOut + YawOut) * ThroMix) ~> 6
     ' Output[OUT_BR] := Thro + (( PitchOut + RollOut - YawOut) * ThroMix) ~> 6
       
     

    Output[0] #>= 1000
    Output[0] <#= 2000
    Output[1] #>= 1000
    Output[1] <#= 2000
    Output[2] #>= 1000
    Output[2] <#= 2000
    Output[3] #>= 1000
    Output[3] <#= 2000
     
    'Copy new Ouput array into servo values
    ESC.Set(  8, Output[0] )
    ESC.Set(  9, Output[1] )
    ESC.Set( 10, Output[2] )
    ESC.Set( 11, Output[3] )


    'Send gyro readings at the end of frame
    dbg.tx( $7f )
    dbg.tx( $7f )
    'OUT_FL = 0                    ' Front Left ESC                       
    'OUT_FR = 1                    ' Front Right ESC
    'OUT_BR = 2                    ' Back Left ESC                        
    'OUT_BL = 3                    ' Back Right ESC
    'dbg.tx( Output[0] >> 8 )    'Front Left = Red
    'dbg.tx( Output[0] )
    'dbg.tx( Output[1] >> 8 )    'Front Right = RED
    'dbg.tx( Output[1] )
    'dbg.tx( Output[2] >> 8 )         'Back Right = Blue
    'dbg.tx( Output[2] )
    'dbg.tx( Output[3] >> 8 )         'Back Left = Blue
    'dbg.tx( Output[3] )
    'dbg.tx( PitchOut >> 8 )         'Back Right = Blue
    'dbg.tx( PitchOut )
    'dbg.tx( RollOut >> 8 )         'Back Left = Blue
    'dbg.tx( RollOut )
    'dbg.tx( YawOut  >> 8 )         'Back Left = BLUE
    'dbg.tx( YawOut ) 
    'dbg.tx( Aile >> 8 )         'Roll = Red
    'dbg.tx( Aile )
    'dbg.tx( DesiredPitch >> 8 )         'Pitch = Green
    'dbg.tx( DesiredPitch )
    'Thro -= 1500
    'dbg.tx( Thro >> 8 )         'Thro  = Blue
    'dbg.tx( Thro )
    'dbg.tx( Rudd >> 8 )         'Thro  = Blue                   
    'dbg.tx( Rudd )
    dbg.tx( iGx >> 8 )             'Green
    dbg.tx( iGx )
    dbg.tx( iGy >> 8 )             'Green
    dbg.tx( iGy )
    dbg.tx( iGz  >> 8 )         'Back Left = BLUE
    dbg.tx( iGz )
    'dbg.tx( Gx >> 8 )             'Red
    'dbg.tx( Gx )
    'dbg.tx( Gy >> 8 )             'Green
    'dbg.tx( Gy )
    'dbg.tx( Gz >> 8 )             'Blue
    'dbg.tx( Gz )
    'dbg.tx( Ax >> 8 )             'Red
    'dbg.tx( Ax )
    'dbg.tx( Ay >> 8 )             'Green
    'dbg.tx( Ay )
    'dbg.tx( Az >> 8 )             'Blue
    'dbg.tx( Az )


    waitcnt( constant(80_000_000 / 250) + LastTime )
    LastTime += constant(80_000_000 / 250)



pub DoConfig | start, end, len, val, i, timer

  'Check the next RX byte for either $A5 or $5A
  waitcnt( 2_000 + cnt )

  start := @ConfigStart
  end := @ConfigEnd
  len := end - start

  end -= 1                      'Makes the loops simpler as they include the last value
   
  val := Dbg.rxCheck
  if( val == $A5 )              '$A5 = Query config

    Dbg.tx( $7f )
    Dbg.tx( $7e )

    Dbg.tx( len>>2 )

    repeat i from start to end
      Dbg.tx( byte[i] )


  elseif( val == $5A )          '$5A = Set config

    if( len == 64 )
      'Get the new configuration data from the serial port and apply it to memory
      repeat i from start to end
        byte[i] := Dbg.rx
       
      Dbg.tx( $7F )               'Send ACK of received config
      Dbg.tx( $70 )
       
      'Write it to EEPROM

      repeat i from start to end step 32
       
        if Eeprom.WritePage(Eeprom#BootPin, Eeprom#EEPROM, i, i, 32)
          Dbg.tx( $7F )
          Dbg.tx( $79 )       'NAK - error
          waitcnt( 8_000_000 + cnt )
          abort ' an error occured during the write
           
        Dbg.tx( $7F )
        Dbg.tx( $71 )
         
        timer := cnt ' prepare to check for a timeout
        repeat while Eeprom.WriteWait(Eeprom#BootPin, Eeprom#EEPROM, i)
          if cnt - timer > clkfreq / 10
            Dbg.tx( $7F )
            Dbg.tx( $79 )     'NAK - error
            waitcnt( 8_000_000 + cnt )
            abort ' waited more than a 1/10 second for the write to finish
         
      Dbg.tx( $7F )
      Dbg.tx( $72 )
      waitcnt( 8_000_000 + cnt )
         
      'Reset the prop
      reboot
       


DAT

ConfigStart

GyroOrientation         long  1                 ' 0 = normal, 1 = rotated 90 CCW, 2 = rotated 90 CW
FrameConfiguration      long  1                 ' 0 = +, 1 = x 

PitchRollControlScale   long  $2000_0000        ' $8000_0000 = * 8 (rapid), $4000_0000 = * 4 (agile), $2000_0000 = * 2 (slower), $1000_0000 = * 1 (beginner)
YawControlScale         long  $1000_0000

PitchRoll_PGain         long  $9_6000
                              '$9_6000           '2400 << 8
                              '$3_E800           '1000 << 8 
PitchRoll_IGain         long  $0  
PitchRoll_DGain         long  $0A00_0000        '2560 << 16
PitchRoll_D2Gain        long  $4000_0000        '16384 << 16

Yaw_PGain               long  $3_E800
                              '$28_0000          '10240 << 8
                              '$13_8800             '5000  << 8 
Yaw_IGain               long  $0  
Yaw_DGain               long  $0A00_0000        '6400 << 16
Yaw_D2Gain              long  $0

ThrottleStartupTime     long  0                 'Hold time in mSec (0 = no throttle range set on startup)

DummyVar0               long  0                 'Padding, to keep the EEPROM write at 64 bytes
DummyVar1               long  0
DummyVar2               long  0

' The previous data is 16 longs, or 64 bytes total
ConfigEnd
  
