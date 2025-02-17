export RobotBasedMagneticFieldStaticProtocolParams, RobotBasedMagneticFieldStaticProtocol, measurement, filename

Base.@kwdef struct RobotBasedMagneticFieldStaticProtocolParams <: RobotBasedProtocolParams
  positions::Union{Positions, Missing} = missing
  postMoveWaitTime::typeof(1.0u"s") = 0.5u"s"
  numCooldowns::Integer = 0
  robotVelocity::typeof(1.0u"m/s") = 0.01u"m/s"
  switchBrakes::Bool = false
end
RobotBasedMagneticFieldStaticProtocolParams(dict::Dict) = createRobotBasedProtocolParams(RobotBasedMagneticFieldStaticProtocolParams, dict)

Base.@kwdef mutable struct RobotBasedMagneticFieldStaticProtocol <: RobotBasedProtocol
  name::AbstractString
  description::AbstractString
  scanner::MPIScanner
  params::RobotBasedMagneticFieldStaticProtocolParams

  biChannel::BidirectionalChannel{ProtocolEvent}
  done::Bool = false
  cancelled::Bool = false
  finishAcknowledged::Bool = false

  executeTask::Union{Task, Nothing} = nothing
  measurement::Union{MagneticFieldMeasurement, Missing} = missing
  filename::Union{AbstractString, Missing} = missing
  safetyTask::Union{Task, Nothing} = nothing
  safetyChannel::Union{Channel{ProtocolEvent}, Nothing} = nothing
end

measurement(protocol::RobotBasedMagneticFieldStaticProtocol) = protocol.measurement
measurement(protocol::RobotBasedMagneticFieldStaticProtocol, measurement::Union{MagneticFieldMeasurement, Missing}) = protocol.measurement = measurement
filename(protocol::RobotBasedMagneticFieldStaticProtocol) = protocol.filename
filename(protocol::RobotBasedMagneticFieldStaticProtocol, filename::String) = protocol.filename = filename

function init(protocol::RobotBasedMagneticFieldStaticProtocol)
  measurement_ = MagneticFieldMeasurement()
  MPIFiles.description(measurement_, "Generated by protocol $(name(protocol)) with the following description: $(description(protocol))")
  MPIFiles.positions(measurement_, positions(protocol))
  measurement(protocol, measurement_)
  # For inner protocol communication
  protocol.safetyChannel = Channel{ProtocolEvent}(32)
  # I'd prefer to only start task during execution and also close it in cleanup
  protocol.safetyTask = @tspawnat protocol.scanner.generalParams.protocolThreadID watchTemperature(protocol.scanner, protocol.safetyChannel)
  # For user I/O
  return BidirectionalChannel{ProtocolEvent}(protocol.biChannel)
end

function preMoveAction(protocol::RobotBasedMagneticFieldStaticProtocol, pos::Vector{<:Unitful.Length})
  if isready(protocol.safetyChannel)
    # Shut down system appropiately and then end execution
    close(protocol.safetyChannel)
    throw(IllegalStateException(take!(protocol.safetyChannel).message))
  end
  @info "moving to position" pos
end

function postMoveAction(protocol::RobotBasedMagneticFieldStaticProtocol, pos::Vector{<:Unitful.Length})
  gaussmeter = getGaussMeter(scanner(protocol))
  field_ = getXYZValues(gaussmeter)
  fieldError_ = calculateFieldError(gaussmeter, field_)
  fieldFrequency_ = getFrequency(gaussmeter)
  timestamp_ = now()
  temperature_ = getTemperature(gaussmeter)

  addMeasuredPosition(measurement(protocol), pos, field=field_, fieldError=fieldError_, fieldFrequency=fieldFrequency_, timestamp=timestamp_, temperature=temperature_)
end

function cleanup(protocol::RobotBasedMagneticFieldStaticProtocol)
  saveMagneticFieldAsHDF5(measurement(protocol), filename(protocol))
  close(protocol.scanner)
end

# Here I'd like to also dispatch on protocol and not only scanner
function watchTemperature(scanner::MPIScanner, channel::Channel)
  while isopen(channel)
    temp = getTemperature(scanner)
    if temp > 1.0
      put!(channel, IllegaleStateEvent("Temperature is too high. Aborting protocol"))
    end
    sleep(0.05)
  end
end

function handleEvent(protocol::RobotBasedMagneticFieldStaticProtocol, event::FinishedAckEvent)
  # End SafetyTask
  close(protocol.safetyChannel)
end
