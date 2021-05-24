export DummyTemperatureSensor, DummyTemperatureSensorParams, numChannels, getTemperature

Base.@kwdef struct DummyTemperatureSensorParams <: DeviceParams
  
end
DummyTemperatureSensorParams(dict::Dict) = params_from_dict(DummyTemperatureSensorParams, dict)

Base.@kwdef mutable struct DummyTemperatureSensor <: TemperatureSensor
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::DummyTemperatureSensorParams
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
end

init(sensor::DummyTemperatureSensor) = nothing
checkDependencies(sensor::DummyTemperatureSensor) = true

numChannels(sensor::DummyTemperatureSensor) = 1
getTemperature(sensor::DummyTemperatureSensor)::Vector{typeof(1u"°C")} = [42u"°C"]
getTemperature(sensor::DummyTemperatureSensor, channel::Int)::typeof(1u"°C") = 42u"°C"