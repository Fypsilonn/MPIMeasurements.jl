__precompile__()
module MPIMeasurements

using Compat
using Reexport
using IniFile
@reexport using MPIFiles
include("Robots/Robots.jl")

if !isdir(Pkg.dir("Redpitaya"))
  println("Installing Redptaya...")
  Pkg.clone("https://github.com/tknopp/Redpitaya.jl.git")
end

if !isdir(Pkg.dir("MPIFiles"))
  println("Installing MPIFiles...")
  Pkg.clone("https://github.com/MagneticParticleImaging/MPIFiles.jl.git")
end

# LibSerialPort currently only supports linux
if is_linux()
  if !isdir(Pkg.dir("LibSerialPort"))
    println("Installing LibSerialPort....")
    Pkg.clone("https://github.com/hofmannmartin/LibSerialPort.jl.git")
    Pkg.build("LibSerialPort")
  end
  using LibSerialPort
  include("SerialDevices/SerialDevices.jl")
end

if !haskey(ENV,"MPILIB_UI")
  ENV["MPILIB_UI"] = "PyPlot"
end


if ENV["MPILIB_UI"] == "PyPlot"
  using PyPlot
end
@reexport using Redpitaya
@reexport using Unitful

include("DAQ/DAQ.jl")
include("TransferFunction/TransferFunction.jl")

end # module
