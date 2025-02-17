import Base: convert

export MPIScanner, MPIScannerGeneral, scannerBoreSize, scannerFacility,
       scannerManufacturer, scannerName, scannerTopology, scannerGradient,
       name, configDir, generalParams, getDevice, getDevices, getSequenceList,
       asyncMeasurement, SequenceMeasState, asyncProducer, prepareAsyncMeasurement,
       getProtocolList, setProtocol, getTransferFunctionList

"""
    $(SIGNATURES)

Recursively find all concrete types of the given type.
"""
function deepsubtypes(type::DataType)
  subtypes_ = subtypes(type)
  allSubtypes = subtypes_
  for subtype in subtypes_
    subsubtypes_ = deepsubtypes(subtype)
    allSubtypes = vcat(allSubtypes, subsubtypes_)
  end
  return allSubtypes
end

"""
    $(SIGNATURES)

Retrieve the concrete type of a given supertype corresponding to a given string.
"""
function getConcreteType(supertype_::DataType, type::String)
  knownTypes = deepsubtypes(supertype_)
  foundImplementation = nothing
  for Implementation in knownTypes
    if string(Implementation) == type
      foundImplementation = Implementation
    end
  end

  if !isnothing(foundImplementation)
    return foundImplementation
  else
    error("The type implied by the string `$type` could not be retrieved since its device struct was not found.")
  end
end

"""
    $(SIGNATURES)

Initiate devices from the given configuration dictionary.

The device types are referenced by strings matching their device struct name.
All device structs are supplied with the device ID and the corresponding
device configuration struct.
"""
function initiateDevices(devicesParams::Dict{String, Any})
  devices = Dict{String, Device}()

  # Get implementations for all devices in the specified order
  for deviceID in devicesParams["initializationOrder"]
    if haskey(devicesParams, deviceID)
      params = devicesParams[deviceID]
      deviceType = pop!(params, "deviceType")

      dependencies_ = Dict{String, Union{Device, Missing}}()
      if haskey(params, "dependencies")
        deviceDepencencies = pop!(params, "dependencies")
        for dependencyID in deviceDepencencies
          dependencies_[dependencyID] = missing
        end
      end

      DeviceImpl = getConcreteType(Device, deviceType)
      DeviceParamsImpl = getConcreteType(DeviceParams, deviceType*"Params") # Assumes the naming convention of ending with [...]Params!

      paramsInst = DeviceParamsImpl(params)
      devices[deviceID] = DeviceImpl(deviceID=deviceID, params=paramsInst, dependencies=dependencies_) # All other fields must have default values!
    else
      throw(ScannerConfigurationError("The device ID `$deviceID` was not found in the configuration. Please check your configuration."))
    end
  end

  # Set dependencies for all devices
  for device in values(devices)
    for dependencyID in keys(dependencies(device))
      device.dependencies[dependencyID] = devices[dependencyID]
    end

    if !checkDependencies(device)
      throw(ScannerConfigurationError("Unspecified dependency error in device with "
                                     *"ID `$(deviceID(device))`. The device depends "
                                     *"on the following device IDs: $(keys(device.dependencies))"))
    end
  end

  # Initiate all devices in the specified order
  for deviceID in devicesParams["initializationOrder"]
    init(devices[deviceID])
    if !isOptional(devices[deviceID]) && !isPresent(devices[deviceID])
      @error "The device with ID `$deviceID` should be present but isn't."
    end
  end

  return devices
end

"""
    $(SIGNATURES)

General description of the scanner.

Note: The fields correspond to the root section of an MDF file.
"""
Base.@kwdef struct MPIScannerGeneral
  "Bore size of the scanner."
  boreSize::typeof(1u"mm")
  "Facility where the scanner is located."
  facility::String
  "Manufacturer of the scanner."
  manufacturer::String
  "Name of the scanner"
  name::String
  "Topology of the scanner, e.g. FFL or FFP."
  topology::String
  "Gradient of the scanners selection field."
  gradient::typeof(1u"T/m")
  "Path of the dataset store."
  datasetStore::String
  "Default sequence of the scanner."
  defaultSequence::String = ""
  "Default protocol of the scanner."
  defaultProtocol::String = ""
  "Location of the scanner's transfer function."
  transferFunction::String = ""
  "Thread ID of the producer thread."
  producerThreadID::Int32 = 2
  "Thread ID of the consumer thread."
  consumerThreadID::Int32 = 3
  "Thread ID of the producer thread."
  protocolThreadID::Int32 = 4
end

abstract type AsyncBuffer end
abstract type AsyncMeasTyp end
struct FrameAveragedAsyncMeas <: AsyncMeasTyp end
struct RegularAsyncMeas <: AsyncMeasTyp end
# TODO Update
asyncMeasType(sequence::Sequence) = acqNumFrameAverages(sequence) > 1 ? FrameAveragedAsyncMeas() : RegularAsyncMeas()

mutable struct FrameAverageBuffer
  buffer::Array{Float32, 4}
  setIndex::Int
end
FrameAverageBuffer(samples, channels, periods, avgFrames) = FrameAverageBuffer(zeros(Float32, samples, channels, periods, avgFrames), 1)

mutable struct SequenceMeasState
  numFrames::Int
  nextFrame::Int
  channel::Union{Channel, Nothing}
  producer::Union{Task,Nothing}
  consumer::Union{Task, Nothing}
  asyncBuffer::AsyncBuffer
  buffer::Array{Float32,4}
  avgBuffer::Union{FrameAverageBuffer, Nothing}
  #temperatures::Matrix{Float64} temps are not implemented atm
  type::AsyncMeasTyp
end


"""
    $(SIGNATURES)

Basic description of a scanner.
"""
mutable struct MPIScanner
  "Name of the scanner"
  name::String
  "Path to the used configuration directory."
  configDir::String
  "General parameters of the scanner like its bore size or gradient."
  generalParams::MPIScannerGeneral
  "Device instances instantiated by the scanner from its configuration."
  devices::Dict{AbstractString, Device}
  seqMeasState::Union{SequenceMeasState, Nothing}

  """
    $(SIGNATURES)

  Initialize a scanner by its name.
  """
  function MPIScanner(name::AbstractString)
    # Search for scanner configurations of the given name in all known configuration directories
    # If you want to add a configuration directory, please use addConfigurationPath(path::String)
    filename = nothing
    configDir = nothing
    for path in scannerConfigurationPath
      configDir = joinpath(path, name)
      if isdir(configDir)
        filename = joinpath(configDir, "Scanner.toml")
        break
      end
    end

    if isnothing(filename)
      throw(ScannerConfigurationError("Could not find a valid configuration for scanner with name `$name`. Search path contains the following directories: $scannerConfigurationPath."))
    end

    @debug "Instantiating scanner `$name` from configuration file at `$filename`."

    params = TOML.parsefile(filename)
    generalParams = params_from_dict(MPIScannerGeneral, params["General"])
    @assert generalParams.name == name "The folder name and the scanner name in the configuration do not match."
    devices = initiateDevices(params["Devices"])

    scanner = new(name, configDir, generalParams, devices, nothing)

    return scanner
  end
end

"""
    $(SIGNATURES)

Close the devices when closing the scanner.
"""
function Base.close(scanner::MPIScanner)
  for device in getDevices(scanner, Device)
    close(device)
  end
end

"Name of the scanner"
name(scanner::MPIScanner) = scanner.name

"Path to the used configuration directory."
configDir(scanner::MPIScanner) = scanner.configDir

"General parameters of the scanner like its bore size or gradient."
generalParams(scanner::MPIScanner) = scanner.generalParams

"Location of the scanner's transfer function."
transferFunction(scanner::MPIScanner) = scanner.generalParams.transferFunction

"Check, whether the scanner has a transfer function defined."
hasTransferFunction(scanner::MPIScanner) = transferFunction(scanner) != ""

"""
    $(SIGNATURES)

Retrieve a device by its `deviceID`.
"""
getDevice(scanner::MPIScanner, deviceID::String) = scanner.devices[deviceID]

"""
    $(SIGNATURES)

Retrieve all devices of a specific `deviceType`. Returns an empty vector if none are found
"""
function getDevices(scanner::MPIScanner, deviceType::Type{<:Device})
  matchingDevices = Vector{Device}()
  for (deviceID, device) in scanner.devices
    if typeof(device) <: deviceType
      push!(matchingDevices, device)
    end
  end
  return matchingDevices
end
function getDevices(scanner::MPIScanner, deviceType::String)
  knownDeviceTypes = deepsubtypes(Device)
  deviceTypeSearched = knownDeviceTypes[findall(type->string(type)==deviceType, knownDeviceTypes)][1]
  return getDevices(scanner, deviceTypeSearched)
end

"""
$(SIGNATURES)

Retrieve all devices of a specific `deviceType` if it can be unambiguously retrieved. Returns nothing if no such device can be found and throws an error if multiple devices fit the type.
"""
function getDevice(scanner::MPIScanner, deviceType::Type{<:Device})
  devices = getDevices(scanner, deviceType)
  if length(devices) > 1
    error("The scanner has more than one $(string(deviceType)) device. Therefore, a single $(string(deviceType)) cannot be retrieved unambiguously.")
  elseif length(devices) == 0
    return nothing
  else 
    return devices[1]
  end
end

"Bore size of the scanner."
scannerBoreSize(scanner::MPIScanner) = scanner.generalParams.boreSize

"Facility where the scanner is located."
scannerFacility(scanner::MPIScanner) = scanner.generalParams.facility

"Manufacturer of the scanner."
scannerManufacturer(scanner::MPIScanner) = scanner.generalParams.manufacturer

"Name of the scanner"
scannerName(scanner::MPIScanner) = scanner.generalParams.name

"Topology of the scanner, e.g. FFL or FFP."
scannerTopology(scanner::MPIScanner) = scanner.generalParams.topology

"Gradient of the scanners selection field."
scannerGradient(scanner::MPIScanner) = scanner.generalParams.gradient

"""
    $(SIGNATURES)

Retrieve a list of all sequences available for the scanner.
"""
function getSequenceList(scanner::MPIScanner)
  path = joinpath(configDir(scanner), "Sequences")
  if isdir(path)
    return String[ splitext(seq)[1] for seq in filter(a->contains(a,".toml"),readdir(path))]
  else
    return String[]
  end
end


"""
    $(SIGNATURES)

Constructor for a sequence of `name` from `configDir`.
"""
function MPIFiles.Sequence(configdir::AbstractString, name::AbstractString)
  path = joinpath(configdir, "Sequences", name*".toml")
  if !isfile(path)
    error("Sequence $(path) not available!")
  end
  return sequenceFromTOML(path)
end

"""
    $(SIGNATURES)

Constructor for a sequence of `name` from the configuration directory specified for the scanner.
"""
MPIFiles.Sequence(scanner::MPIScanner, name::AbstractString) = Sequence(configDir(scanner), name)

function getTransferFunctionList(scanner::MPIScanner)
  path = joinpath(configDir(scanner), "TransferFunctions")
  if isdir(path)
    return String[ splitext(seq)[1] for seq in filter(a->contains(a,".h5"),readdir(path))]
  else
    return String[]
  end
end

function MPIFiles.TransferFunction(configdir::AbstractString, name::AbstractString)
  path = joinpath(configdir, "TransferFunctions", name*".h5")
  if !isfile(path)
    error("TransferFunction $(path) not available!")
  end
  return TransferFunction(path)
end

MPIFiles.TransferFunction(scanner::MPIScanner) = TransferFunction(configDir(scanner),transferFunction(scanner))

#### Scanner Measurement Functions ####
####  Async version  ####
SequenceMeasState() = SequenceMeasState(0, 1, nothing, nothing, nothing, DummyAsyncBuffer(nothing), zeros(Float64,0,0,0,0), nothing, RegularAsyncMeas())

function asyncMeasurement(scanner::MPIScanner, sequence::Sequence)
  prepareAsyncMeasurement(scanner, sequence)
  scanner.seqMeasState.producer = @tspawnat scanner.generalParams.producerThreadID asyncProducer(scanner.seqMeasState.channel, scanner, sequence)
  bind(scanner.seqMeasState.channel, scanner.seqMeasState.producer)
  scanner.seqMeasState.consumer = @tspawnat scanner.generalParams.consumerThreadID asyncConsumer(scanner.seqMeasState.channel, scanner)
  return scanner.seqMeasState
end

function prepareAsyncMeasurement(scanner::MPIScanner, sequence::Sequence)
  daq = getDAQ(scanner)
  numFrames = acqNumFrames(sequence)
  rxNumSamplingPoints = rxNumSamplesPerPeriod(sequence)
  numPeriods = acqNumPeriodsPerFrame(sequence)
  frameAverage = acqNumFrameAverages(sequence)
  setup(daq, sequence)

  # Prepare buffering structures
  @info "Allocating buffer for $numFrames frames"
  # TODO implement properly with only RxMeasurementChannels
  buffer = zeros(Float32,rxNumSamplingPoints, length(rxChannels(sequence)),numPeriods,numFrames)
  #buffer = zeros(Float32,rxNumSamplingPoints,numRxChannelsMeasurement(daq),numPeriods,numFrames)
  avgBuffer = nothing
  if frameAverage > 1
    avgBuffer = FrameAverageBuffer(zeros(Float32, frameAverageBufferSize(daq, frameAverage)), 1)
  end
  channel = Channel{channelType(daq)}(32)

  # Prepare measState
  measState = SequenceMeasState(numFrames, 1, nothing, nothing, nothing, AsyncBuffer(daq), buffer, avgBuffer, asyncMeasType(sequence))
  measState.channel = channel

  scanner.seqMeasState = measState
end

function asyncProducer(channel::Channel, scanner::MPIScanner, sequence::Sequence; prepTx = true)
  su = getSurveillanceUnit(scanner) # Maybe also support multiple SU units?
  if !isnothing(su)
    enableACPower(su)
    # TODO Send expected enable time to SU
  end
  robots = getRobots(scanner)
  for robot in robots
    disable(robot)
  end

  daq = getDAQ(scanner)
  asyncProducer(channel, daq, sequence, prepTx = prepTx)

  if !isnothing(su)
    disableACPower(su)
  end
  for robot in robots
    enable(robot)
  end
 
end

# Default Consumer
function asyncConsumer(channel::Channel, scanner::MPIScanner)
  daq = getDAQ(scanner)
  measState = scanner.seqMeasState

  @info "Consumer start"
  while isopen(channel) || isready(channel)
    while isready(channel)
      chunk = take!(channel)
      updateAsyncBuffer!(measState.asyncBuffer, chunk)
      updateFrameBuffer!(measState, daq)
    end
    sleep(0.001)
  end
  @info "Consumer end"

  # TODO calibTemperatures is not filled in asyncVersion yet, would need own innerAsyncConsumer
  #if length(measState.temperatures) > 0
  #  params["calibTemperatures"] = measState.temperatures
  #end
end

#### Protocol ####
function getProtocolList(scanner::MPIScanner)
  path = joinpath(configDir(scanner), "Protocols/")
  if isdir(path)
    return String[ splitext(proto)[1] for proto in filter(a->contains(a,".toml"),readdir(path))]
  else
    return String[]
  end
end

function execute(scanner::MPIScanner, protocol::Protocol)
  return execute(protocol, scanner.generalParams.protocolThreadID)
end
