using Unitful

export BrukerRobot, BrukerRobotParams

export moveCenter, movePark


Base.@kwdef struct BrukerRobotParams <: DeviceParams
  connectionName::String = "RobotServer"
  axisRange::Vector{Vector{typeof(1.0u"mm")}} = [[-85.0,225.0], [-Inf, Inf], [-Inf, Inf]]u"mm"
  namedPositions::Dict{String, Vector{typeof(1.0u"mm")}} = Dict("origin" => [0,0,0]u"mm")
end

BrukerRobotParams(dict::Dict) = params_from_dict(BrukerRobotParams, dict)

Base.@kwdef mutable struct BrukerRobot <: Robot
  "Unique device ID for this device as defined in the configuration."
  deviceID::String
  "Parameter struct for this devices read from the configuration."
  params::BrukerRobotParams
  "Flag if the device is optional."
  optional::Bool = false
  "Flag if the device is present."
  present::Bool = false
  "Vector of dependencies for this device."
  dependencies::Dict{String, Union{Device, Missing}}
  state::RobotState = INIT
end

""" `BrukerCommand(command::String)` """
struct BrukerCommand
  command::String
end

# Useful links
# http://unix.stackexchange.com/questions/87831/how-to-send-keystrokes-f5-from-terminal-to-a-process
# 
# https://github.com/JuliaLang/julia/pull/6948
# 
# Kind of deprecated:
# http://blog.leahhanson.us/post/julia/julia-commands.html

const center = "center\n"
const park = "park\n"
const pos = "pos\n"
const quit = "quit\n"
const exit = "exit\n"
const err = "err?\n"


dof(rob::BrukerRobot) = 3
axisRange(rob::BrukerRobot) = rob.params.axisRange
defaultVelocity(rob::BrukerRobot) = nothing
_getPosition(rob::BrukerRobot) = sendCommand(rob, BrukerCommand(pos))
_isReferenced(rob::BrukerRobot) = true
_enable(rob::BrukerRobot) = nothing
_disable(rob::BrukerRobot) = nothing
_reset(rob::BrukerRobot) = nothing
_setup(rob::BrukerRobot) = nothing
_doReferenceDrive(rob::BrukerRobot) = nothing


""" Move Bruker Robot to center"""
function moveCenter(sd::BrukerRobot)
    sendCommand(sd, BrukerCommand(center))
end

""" Move Bruker Robot to park"""
function movePark(sd::BrukerRobot)
    sendCommand(sd, BrukerCommand(park))
end

function _moveAbs(rob::BrukerRobot, pos::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
    if speed !== nothing
        @warn "BrukerRobot does not support setting velocities!"
    end
    cmd = BrukerCommand("goto $(ustrip(Float64, u"mm", pos[1])),$(ustrip(Float64, u"mm", pos[2])),$(ustrip(Float64, u"mm", pos[3]))\n")
    res = sendCommand(rob, cmd)
end

""" Not Implemented """
function _moveRel(rob::BrukerRobot, dist::Vector{<:Unitful.Length}, speed::Union{Vector{<:Unitful.Velocity},Nothing})
    error("BrukerRobot does not support moveRel")
end


""" Send Command `sendCommand(sd::BrukerRobot, brukercmd::BrukerCommand)`"""
function sendCommand(sd::BrukerRobot, brukercmd::BrukerCommand)

    (result, startmovetime, endmovetime) = _sendCommand(sd, brukercmd)
    
    if result == "0\n"
        return true
    elseif length(split(result, ",")) == 3
        @info "$(brukercmd.command) returned position: $(result)"
        return parse.(Float64, split(result, ",")) * u"mm"
    elseif result == "?\n"
        @warn "$(brukercmd.command) is unknown! Try again..."
        return false
    elseif result == "!\n"
        throw(ErrorException("Error during command $(brukercmd.command) execution."))
    else
        throw(ErrorException("$(brukercmd.command) has unexpected result $(result)"))
    end
end

function _sendCommand(sd::BrukerRobot, brukercmd::BrukerCommand)
    p = open(`$(sd.params.connectionName)`, "r+");
  # p = open(`cat`,"r+");
    startmovetime = now(Dates.UTC)
    writetask = write(p.in, brukercmd.command)
    writetaskexit = write(p.in, exit)
    readtask = @async readavailable(p.out)
    wait(readtask)
    endmovetime = now(Dates.UTC)
    if readtask.state == :done
        return (ascii(String(readtask.result)), startmovetime, endmovetime);
    else
        @error "end" readTask.state readTask.exception
        return readtask.exception
    end
end
