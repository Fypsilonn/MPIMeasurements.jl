params = SimulatedAmplifierParams()
amp = SimulatedAmplifier(deviceID="simAmp", params=params, dependencies=Dict{String, Union{Device, Missing}}())

@test state(amp) == false # default
@test mode(amp) == AMP_VOLTAGE_MODE # Safe default
@test voltageMode(amp) == AMP_LOW_VOLTAGE_MODE # Safe default
@test matchingNetwork(amp) == 1 # default

turnOn(amp)
@test state(amp) == true

turnOff(amp)
@test state(amp) == false

mode(amp, AMP_CURRENT_MODE)
@test mode(amp) == AMP_CURRENT_MODE

mode(amp, AMP_VOLTAGE_MODE)
@test mode(amp) == AMP_VOLTAGE_MODE

voltageMode(amp, AMP_HIGH_VOLTAGE_MODE)
@test voltageMode(amp) == AMP_HIGH_VOLTAGE_MODE

voltageMode(amp, AMP_LOW_VOLTAGE_MODE)
@test voltageMode(amp) == AMP_LOW_VOLTAGE_MODE

matchingNetwork(amp, 2)
@test matchingNetwork(amp) == 2

@test temperature(amp) == 25.0u"°C"

toCurrentMode(amp)
@test mode(amp) == AMP_CURRENT_MODE

toVoltageMode(amp)
@test mode(amp) == AMP_VOLTAGE_MODE

toLowVoltageMode(amp)
@test voltageMode(amp) == AMP_LOW_VOLTAGE_MODE

toHighVoltageMode(amp)
@test voltageMode(amp) == AMP_HIGH_VOLTAGE_MODE