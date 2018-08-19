export measurement, measurementCont, measurementRepeatability

function measurement(daq::AbstractDAQ, params_::Dict;
                     kargs... )
  updateParams!(daq, params_)
  measurement_(daq; kargs...)
end

function measurement_(daq::AbstractDAQ; controlPhase=daq.params.controlPhase )

  startTx(daq)
  if controlPhase
    controlLoop(daq)
  else
    setTxParams(daq, daq.params.calibFieldToVolt.*daq.params.dfStrength,
                     zeros(numTxChannels(daq)))
  end

  currFr = enableSlowDAC(daq, true, daq.params.acqNumFrames*daq.params.acqNumFrameAverages,
                         daq.params.ffRampUpTime, daq.params.ffRampUpFraction)

  uMeas, uRef = readData(daq, daq.params.acqNumFrames*daq.params.acqNumFrameAverages, currFr)

  stopTx(daq)
  disconnect(daq)

  if daq.params.acqNumFrameAverages > 1
    u_ = reshape(uMeas, size(uMeas,1), size(uMeas,2), size(uMeas,3),
                daq.params.acqNumFrames,daq.params.acqNumFrameAverages)
    uMeasAv = mean(u_, 5)[:,:,:,:,1]
    return uMeasAv
  else
    return uMeas
  end
end

# high level: This stores as MDF
function measurement(daq::AbstractDAQ, params_::Dict, filename::String;
                     bgdata=nothing, kargs...)

  params = copy(params_)
  #merge!(params, toDict(daq.params))

  # measurement
  #params["acqNumFrames"] = params["acqNumFGFrames"]
  uFG = measurement(daq, params; kargs...)

  # acquisition parameters
  params["acqStartTime"] = Dates.unix2datetime(time())
  params["acqGradient"] = addTrailingSingleton([0.0;0.0;0.0],2) #FIXME
  params["acqOffsetField"] = addTrailingSingleton([0.0;0.0;0.0],2) #FIXME

  # drivefield parameters
  params["dfStrength"] = reshape(daq.params.dfStrength,1,length(daq.params.dfStrength),1)
  params["dfPhase"] = reshape(daq.params.dfPhase,1,length(daq.params.dfPhase),1)
  divider = div.(daq.params.dfDivider,daq.params.decimation)
  params["dfDivider"] = reshape(divider,1,length(divider))

  # receiver parameters
  params["rxNumSamplingPoints"] = daq.params.rxNumSamplingPoints
  params["rxNumChannels"] = numRxChannels(daq)

  # transferFunction
  if haskey(params, "transferFunction") && params["transferFunction"] != ""
    numFreq = div(params["rxNumSamplingPoints"],2)+1
    freq = collect(0:(numFreq-1))./(numFreq-1).*daq.params.rxBandwidth
    tf = zeros(ComplexF64, numFreq, numRxChannels(daq) )
    tf_ = tf_receive_chain(params["transferFunction"])
    for d=1:numRxChannels(daq)
      tf[:,d] = tf_[freq,d]
    end
    params["rxTransferFunction"] = tf
    params["rxInductionFactor"] = tf_.inductionFactor
  end

  # calibration params  (needs to be called after calibration params!)
  calib = zeros(2,numRxChannels(daq))
  calib[1,:] = 1.0
  params["rxDataConversionFactor"] = calib # calibIntToVoltRx(daq)

  params["measIsFourierTransformed"] = false
  params["measIsSpectralLeakageCorrected"] = false
  params["measIsTFCorrected"] = false
  params["measIsFrequencySelection"] = false
  params["measIsBGCorrected"] = false
  params["measIsTransposed"] = false
  params["measIsFramePermutation"] = false

  if bgdata == nothing
    params["measIsBGFrame"] = zeros(Bool,params["acqNumFrames"])
    params["measData"] = uFG
    #params["acqNumFrames"] = params["acqNumFGFrames"]
  else
    numBGFrames = size(bgdata,4)
    params["measData"] = cat(bgdata,uFG,dims=4)
    params["measIsBGFrame"] = cat(ones(Bool,numBGFrames), zeros(Bool,params["acqNumFrames"]), dims=1)
    params["acqNumFrames"] = params["acqNumFrames"] + numBGFrames
  end

  MPIFiles.saveasMDF( filename, params )
  return filename
end


function measurement(daq::AbstractDAQ, params::Dict, mdf::MDFDatasetStore;
                     kargs...)
  #merge!(daq.params, params)

  name = params["studyName"]
  path = joinpath( studydir(mdf), name)
  subject = ""
  date = ""

  newStudy = Study(path,name,subject,date)

  addStudy(mdf, newStudy)
  expNum = getNewExperimentNum(mdf, newStudy)

  #daq["studyName"] = params["studyName"]
  params["experimentNumber"] = expNum

  filename = joinpath(studydir(mdf),newStudy.name,string(expNum)*".mdf")
  measurement(daq, params, filename; kargs...)
  return filename
end


export loadBGCorrData
function loadBGCorrData(filename)
  f = MPIFiles.MPIFile(filename)
  u = MPIFiles.measData(f)[:,1,1,measFGFrameIdx(f)]
  if acqNumBGFrames(f) > 0
    uBG = MPIFiles.measData(f)[:,1,1,measBGFrameIdx(f)]
    uBGMean = mean(uBG[:,:],2)
    u[:] .-= uBGMean
  end
  return u
end

function measurementCont(daq::AbstractDAQ, params::Dict=Dict{String,Any}();
                        controlPhase=true, showFT=true)
  println("Starting Measurement...")

  if !isempty(params)
    updateParams!(daq, params)
  end

  startTx(daq)

  if controlPhase
    controlLoop(daq)
  else
    setTxParams(daq, daq.params.calibFieldToVolt.*daq.params.dfStrength,
                     zeros(numTxChannels(daq)))
    sleep(daq.params.controlPause)
  end

  try
      while true
        uMeas, uRef = readData(daq, 1, currentFrame(daq))
        #showDAQData(daq,vec(uMeas))
        amplitude, phase = calcFieldFromRef(daq,uRef)
        println("reference amplitude=$amplitude phase=$phase")

        u = cat(uMeas, uRef, dims=2)
        #showAllDAQData(uMeas,1)
        #showAllDAQData(uRef,2)
        showAllDAQData(u, showFT=showFT)
        sleep(0.2)
      end
  catch x
      if isa(x, InterruptException)
          println("Stop Tx")
          stopTx(daq)
          disconnect(daq)
      else
        rethrow(x)
      end
  end
  return nothing
end

export measurementContReadAndSave
function measurementContReadAndSave(daq::AbstractDAQ, robot, params::Dict=Dict{String,Any}();
                        controlPhase=true, showFT=true)
  if !isempty(params)
    updateParams!(daq, params)
  end

  startTx(daq)

  if controlPhase
    controlLoop(daq)
  else
    setTxParams(daq, daq.params.calibFieldToVolt.*daq.params.dfStrength,
                     zeros(numTxChannels(daq)))
    sleep(daq.params.controlPause)
  end

  uMeas, uRef = readData(daq, 1, currentFrame(daq))

  x  = [0.0;collect(156 + linspace(-40,40,9))]
  xx = cat(x,x,x,dims=1)
  y = repeat([-11.2],inner=10)
  yy = cat(y-10.0,y,y+10.0,dims=1)
  S = zeros(length(uMeas),length(xx))
  readline(stdin)

  try
      for k=1:length(xx)
        moveAbs(robot,xx[k]*1.0Unitful.mm,yy[k]*1.0Unitful.mm,71.0Unitful.mm)
        sleep(6.0)

        uMeas, uRef = readData(daq, 1, currentFrame(daq))
        #showDAQData(daq,vec(uMeas))
        amplitude, phase = calcFieldFromRef(daq,uRef)
        println("reference amplitude=$amplitude phase=$phase")

        u = cat(uMeas, uRef, dims=2)
        #showAllDAQData(uMeas,1)
        #showAllDAQData(uRef,2)
        showAllDAQData(u, showFT=showFT)

        S[:,k] = vec(uMeas)
        println("New Pos")
      end
  catch x
      if isa(x, InterruptException)
          println("Stop Tx")
          stopTx(daq)
          disconnect(daq)
      else
        rethrow(x)
      end
  end

  yy = collect(-11.2 + linspace(-40,40,9))
  S2 = zeros(length(uMeas),length(yy))

  println("switch the phantoms")
  readline(stdin)

  try
      for k=1:length(yy)
        moveAbs(robot,146.0Unitful.mm,yy[k]*1.0Unitful.mm,81.0Unitful.mm)
        sleep(6.0)

        uMeas, uRef = readData(daq, 1, currentFrame(daq))
        #showDAQData(daq,vec(uMeas))
        amplitude, phase = calcFieldFromRef(daq,uRef)
        println("reference amplitude=$amplitude phase=$phase")

        u = cat(uMeas, uRef, dims=2)
        #showAllDAQData(uMeas,1)
        #showAllDAQData(uRef,2)
        showAllDAQData(u, showFT=showFT)

        S2[:,k] = vec(uMeas)
        println("New Pos")
      end
  catch x
      if isa(x, InterruptException)
          println("Stop Tx")
          stopTx(daq)
          disconnect(daq)
      else
        rethrow(x)
      end
  end



  stopTx(daq)
  disconnect(daq)
  return S,S2
end











function measurementRepeatability(daq::AbstractDAQ, filename::String, numRepetitions,
                                  delay,
                params_=Dict{String,Any}();
                     kargs...)
  merge!(daq.params, params_)

  params = copy(daq.params)

  # acquisition parameters
  params["acqStartTime"] = Dates.unix2datetime(time())
  params["acqGradient"] = addTrailingSingleton([0.0;0.0;0.0],2) #FIXME
  params["acqOffsetField"] = addTrailingSingleton([0.0;0.0;0.0],2) #FIXME

  # drivefield parameters
  params["dfStrength"] = reshape(daq["dfStrength"],1,length(daq["dfStrength"]),1)
  params["dfPhase"] = reshape(daq["dfPhase"],1,length(daq["dfPhase"]),1)
  params["dfDivider"] = reshape(daq["dfDivider"],1,length(daq["dfDivider"]))

  # receiver parameters
  params["rxNumSamplingPoints"] = daq["numSampPerPeriod"] #FIXME rename internally

  # transferFunction
  if params["transferFunction"] != ""
    numFreq = div(params["rxNumSamplingPoints"],2)+1
    freq = collect(0:(numFreq-1))./(numFreq-1).*daq["rxBandwidth"]
    tf = zeros(ComplexF64, numFreq, numRxChannels(daq) )
    tf_ = tf_receive_chain(params["transferFunction"])
    for d=1:numRxChannels(daq)
      tf[:,d] = tf_[freq,d]
    end
    params["rxTransferFunction"] = tf
    params["rxInductionFactor"] = tf_.inductionFactor
  end

  # measurement
  bgdata = measurement(daq; kargs...)
  readline(stdin)

  # measurement
  uFG = zeros(Int16, daq["numSampPerPeriod"],numRxChannels(daq),
                  daq["acqNumPeriodsPerFrame"],daq["acqNumFGFrames"],numRepetitions)


  @showprogress 1 "Computing..."  for l=1:numRepetitions
    uFG[:,:,:,:,l] = measurement(daq; kargs...)
    sleep(delay)
  end

  uFG = reshape(uFG, Val{4})

  # calibration params  (needs to be called after calibration params!)
  params["rxDataConversionFactor"] = dataConversionFactor(daq)

  numBGFrames = size(bgdata,4)
  params["measData"] = cat(bgdata,uFG, dims=4)
  params["measIsBGFrame"] = cat(ones(Bool,numBGFrames),
                                zeros(Bool,daq["acqNumFGFrames"]*numRepetitions), dims=1)
  params["acqNumFrames"] = daq["acqNumFGFrames"]*numRepetitions + numBGFrames

  MPIFiles.saveasMDF( filename, params )
  return filename
end



function measurementRepeatability(daq::AbstractDAQ, mdf::MDFDatasetStore, numRepetitions,
                                  delay, params=Dict{String,Any};
                     kargs...)
  merge!(daq.params, params)

  name = params["studyName"]
  path = joinpath( studydir(mdf), name)
  subject = ""
  date = ""

  newStudy = Study(path,name,subject,date)

  addStudy(mdf, newStudy)
  expNum = getNewExperimentNum(mdf, newStudy)

  daq["studyName"] = params["studyName"]
  daq["experimentNumber"] = expNum

  filename = joinpath(studydir(mdf),newStudy.name,string(expNum)*".mdf")
  measurementRepeatability(daq, filename, numRepetitions, delay; kargs...)
  return filename
end
