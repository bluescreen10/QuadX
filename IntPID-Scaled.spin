CON
  MaxOutput = 450
  MaxError = 65536  

VAR
  long Kp             'PID Gain
  long Ki             'PID Gain
  long Kd             'PID Gain
  long Kd2            'PID Gain
  long LastPError     'Previous Error
  long LastDError     'Previous Error
  long Output         'PID Output
  long IError         'Accumulated integral error
  long PError, DError, D2Error

   
PUB Init( PGain, IGain, DGain )
  Kp := PGain
  Ki := IGain
  Kd := DGain
  Kd2 := 0

  LastPError := 0
  IError := 0


PUB SetPGain( Value )
  Kp := Value  

PUB SetIGain( Value )
  Ki := Value  

PUB SetDGain( Value )
  Kd := Value

PUB SetD2Gain( Value )
  Kd2 := Value

PUB ResetIntegralError
  IError := 0

  
   
PUB Calculate( SetPoint , Measured )

  ' Proportional error is Desired - Measured
  PError := SetPoint - Measured
  
  ' Derivative error is the delta PError divided by time
  ' If loop timing is const, you can skip the divide and just make the factor smaller
  DError := PError - LastPError
  D2Error := DError - LastDError  

  LastDError := DError
  LastPError := PError

  Output := (Kp ** PError) + (Kd ** DError) + (Kd2 ** D2Error) + (Ki ** IError)
  
  'Accumulate Integral error *or* Limit output. 
  'Stop accumulating when output saturates 
     
  Output <#= MaxOutput
  Output #>= -MaxOutput 

  IError += PError 
  IError #>= -MaxError
  IError <#=  MaxError

  return Output 