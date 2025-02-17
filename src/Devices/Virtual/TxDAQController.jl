export TxDAQControllerParams, TxDAQController, controlTx

Base.@kwdef mutable struct TxDAQControllerParams <: DeviceParams
  phaseAccuracy::Float64
  amplitudeAccuracy::Float64
  controlPause::Float64
  maxControlSteps::Int64 = 20
  correctCrossCoupling::Bool = false
end
TxDAQControllerParams(dict::Dict) = params_from_dict(TxDAQControllerParams, dict)

struct ControlledChannel
  seqChannel::PeriodicElectricalChannel
  daqChannel::TxChannelParams
end

Base.@kwdef mutable struct TxDAQController <: VirtualDevice
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::TxDAQControllerParams
  "Flag if the device is optional."
	optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}

  currTx::Union{Matrix{ComplexF64}, Nothing} = nothing
  desiredTx::Union{Matrix{ComplexF64}, Nothing} = nothing
  sinLUT::Union{Matrix{Float64}, Nothing} = nothing
  cosLUT::Union{Matrix{Float64}, Nothing} = nothing
  controlledChannels::Vector{ControlledChannel} = []
end

function init(tx::TxDAQController)
  @info "Initializing TxDAQController with ID `$(tx.deviceID)`."
  tx.present = true
end

neededDependencies(::TxDAQController) = [AbstractDAQ]
optionalDependencies(::TxDAQController) = []

function controlTx(txCont::TxDAQController, seq::Sequence, initTx::Union{Matrix{ComplexF64}, Nothing} = nothing)
  # Prepare and check channel under control
  daq = dependency(txCont, AbstractDAQ)
  seqControlledChannel = getControlledChannel(seq)
  missingControlDef = []
  txCont.controlledChannels = []
  for seqChannel in seqControlledChannel
    name = id(seqChannel)
    daqChannel = get(daq.params.channels, name, nothing)
    if isnothing(daqChannel) || isnothing(daqChannel.feedback) || !in(daqChannel.feedback.channelID, daq.refChanIDs)
      push!(missingControlDef, name)
    else 
      push!(txCont.controlledChannels, ControlledChannel(seqChannel, daqChannel))
    end
  end
  if length(missingControlDef) > 0
    message = "The sequence requires control for the following channel " * join(string.(missingControlDef), ", ", " and") * ", but either the channel was not defined or had no defined feedback channel."
    throw(IllegalStateException(message))
  end

  # Check that channels only have one component
  if any(x -> length(x.components) > 1, seqControlledChannel)
    throw(IllegalStateException("Sequence has channel with more than one component. Such a channel cannot be controlled by this controller"))
  end

  if !isnothing(initTx) 
    s = size(initTx)
    # Not square or does not fit controlled channel matrix
    if !(length(s) == 0 || all(isequal(s[1]), s))
      throw(IllegalStateException("Given initTx for control tx has dimenions $s that is either not square or does not match the amount of controlled channel"))
    end
  end

  # Prepare values
  if isnothing(initTx)
    txCont.currTx = convert(Matrix{ComplexF64}, diagm(ustrip.(u"V", [channel.daqChannel.limitPeak/10 for channel in txCont.controlledChannels])))
  else 
    txCont.currTx = initTx
  end
  sinLUT, cosLUt = createLUTs(seqControlledChannel, seq::Sequence)
  txCont.sinLUT = sinLUT
  txCont.cosLUT = cosLUt
  Ω = calcDesiredField(seqControlledChannel)

  # Start Tx
  setTxParams(daq, txFromMatrix(txCont, txCont.currTx)...)
  startTx(daq)

  controlPhaseDone = false
  i = 1
  while !controlPhaseDone && i <= txCont.params.maxControlSteps
    @info "CONTROL STEP $i"
    period = currentPeriod(daq)
    uMeas, uRef = readDataPeriods(daq, 1, period + 1, acqNumAverages(seq))

    controlPhaseDone = doControlStep(txCont, seq, uRef, Ω)

    sleep(txCont.params.controlPause)
    i += 1
  end
  stopTx(daq)
  setTxParams(daq, txFromMatrix(txCont, txCont.currTx)...)
  return txFromMatrix(txCont, txCont.currTx)
end

getControlledChannel(seq::Sequence) = [channel for field in seq.fields if field.control for channel in field.channels if typeof(channel) <: PeriodicElectricalChannel]

function txFromMatrix(txCont::TxDAQController, Γ::Matrix{ComplexF64})
  amplitudes = Dict{String, Vector{Union{Float32, Nothing}}}()
  phases = Dict{String, Vector{Union{Float32, Nothing}}}()
  for (d, channel) in enumerate(txCont.controlledChannels)
    amps = []
    phs = []
    for (e, channel) in enumerate(txCont.controlledChannels)
      push!(amps, abs(Γ[d, e]))
      push!(phs, angle(Γ[d, e]))
    end
    amplitudes[id(channel.seqChannel)] = amps
    phases[id(channel.seqChannel)] = phs
  end
  return amplitudes, phases
end

function createLUTs(seqChannel::Vector{PeriodicElectricalChannel}, seq::Sequence)
  N = rxNumSamplingPoints(seq)
  D = length(seqChannel)
  cycle = ustrip(dfCycle(seq))
  base = ustrip(dfBaseFrequency(seq))
  dfFreq = [base/x.components[1].divider for x in seqChannel]
  
  sinLUT = zeros(N,D)
  cosLUT = zeros(N,D)
  for d=1:D
    Y = round(Int64, cycle*dfFreq[d] )
    for n=1:N
      sinLUT[n,d] = sin(2 * pi * (n-1) * Y / N) / N #sqrt(N)*2
      cosLUT[n,d] = cos(2 * pi * (n-1) * Y / N) / N #sqrt(N)*2
    end
  end
  return sinLUT, cosLUT
end

function doControlStep(txCont::TxDAQController, seq::Sequence, uRef, Ω::Matrix)

  Γ = calcFieldFromRef(txCont,seq, uRef)
  daq = dependency(txCont, AbstractDAQ)

  @info "reference Γ=" Γ

  if controlStepSuccessful(Γ, Ω, txCont)
    @info "Could control"
    return true
  else
    newTx = newDFValues(Γ, Ω, txCont)
    oldTx = txCont.currTx
    @info "oldTx=" oldTx 
    @info "newTx=" newTx

    if checkDFValues(newTx, oldTx, Γ,txCont)
      txCont.currTx[:] = newTx
      setTxParams(daq, txFromMatrix(txCont, txCont.currTx)...)
    else
      @warn "New values are above voltage limits or are different than expected!"
    end

    @info "Could not control !"
    return false
  end
end

function calcFieldFromRef(txCont::TxDAQController, seq::Sequence, uRef)
  len = length(txCont.controlledChannels)
  Γ = zeros(ComplexF64, len, len)

  for d=1:len
    for e=1:len
      c = ustrip(u"T/V", txCont.controlledChannels[d].daqChannel.feedback.calibration)

      uVolt = float(uRef[1:rxNumSamplingPoints(seq),d,1])

      a = 2*sum(uVolt.*txCont.cosLUT[:,e])
      b = 2*sum(uVolt.*txCont.sinLUT[:,e])

      Γ[d,e] = c*(b+im*a)
    end
  end
  return Γ
end

function calcDesiredField(seqChannel::Vector{PeriodicElectricalChannel})
  temp = [ustrip(amplitude(ch.components[1])) * exp(im*ustrip(phase(ch.components[1]))) for ch in seqChannel]
  return convert(Matrix{ComplexF64}, diagm(temp))
end

function controlStepSuccessful(Γ::Matrix, Ω::Matrix, txCont::TxDAQController)

  if txCont.params.correctCrossCoupling
    diff = Ω - Γ
  else
    diff = diagm(diag(Ω)) - diagm(diag(Γ))
  end
  deviation = maximum(abs.(diff)) / maximum(abs.(Ω))
  @info "Ω = " Ω
  @info "Γ = " Γ
  @info "Ω - Γ = " diff
  @info "deviation = $(deviation)   allowed= $(txCont.params.amplitudeAccuracy)"
  return deviation < txCont.params.amplitudeAccuracy
end

function newDFValues(Γ::Matrix, Ω::Matrix, txCont::TxDAQController)

  κ = txCont.currTx
  if txCont.params.correctCrossCoupling
    β = Γ*inv(κ)
  else 
    @show size(Γ), size(κ)
    β = diagm(diag(Γ))*inv(diagm(diag(κ))) 
  end
  newTx = inv(β)*Ω

  @warn "here are the values"
  @show κ
  @show Γ
  @show Ω
  

  return newTx
end

function checkDFValues(newTx, oldTx, Γ, txCont::TxDAQController)

  calibFieldToVoltEstimate = [ustrip(u"V/T", ch.daqChannel.calibration) for ch in txCont.controlledChannels]
  calibFieldToVoltMeasured = abs.(diag(oldTx) ./ diag(Γ))

  @info "" calibFieldToVoltEstimate[1] calibFieldToVoltMeasured[1]

  deviation = abs.(1.0 .- calibFieldToVoltMeasured./calibFieldToVoltEstimate)

  @info "We expected $(calibFieldToVoltEstimate) and got $(calibFieldToVoltMeasured), deviation: $deviation"

  return all( abs.(newTx) .<  ustrip.(u"V", [channel.daqChannel.limitPeak for channel in txCont.controlledChannels]) ) && maximum( deviation ) < 0.2
end