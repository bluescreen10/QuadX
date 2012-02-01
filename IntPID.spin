CON
  MaxOutput = 400
  MaxError = 512  

VAR
  long Kp             'PID Gain
  long Ki             'PID Gain
  long Kd             'PID Gain
  long LastPError     'Previous Error
  long Output         'PID Output
  long IError         'Accumulated integral error
  long PError, DError

  long LastPOut
  long LastDOut

   
PUB Init( PGain, IGain, DGain )
  Kp := PGain
  Ki := IGain
  Kd := DGain

  LastPError := 0
  IError := 0


PUB SetPGain( Value )
  Kp := Value  

PUB SetIGain( Value )
  Ki := Value  

PUB SetDGain( Value )
  Kd := Value

PUB ResetIntegralError
  IError := 0

PUB GetPOut
  return LastPOut

PUB GetDOut
  return LastDOut

  
   
PUB Calculate( SetPoint , Measured )

  ' Proportional error is Desired - Measured
  PError := SetPoint - Measured
  
  ' Derivative error is the delta PError divided by time
  ' If loop timing is const, you can skip the divide and just make the factor smaller
  DError := PError - LastPError  
  LastPError := PError
  PError ~>= 8 

  LastPOut := (Kp * PError) ~> 4
  LastDOut := (Kd * DError) ~> 8
    
  Output := (Kp * PError) + (Kd * DError) + (Ki * IError)
  Output := Output ~> 8
  
  'Accumulate Integral error *or* Limit output. 
  'Stop accumulating when output saturates 
     
  Output <#= MaxOutput
  Output #>= -MaxOutput 

  IError += PError 
  IError #>= -MaxError
  IError <#=  MaxError

  return Output 