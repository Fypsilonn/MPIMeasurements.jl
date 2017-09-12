using MPIMeasurements
using Base.Test
using Unitful
using Compat
using HDF5

# define Grid
shp = [10,10,1]
fov = [10.0,10.0,1.0]u"mm"
ctr = [0,0,0]u"mm"
positions = CartesianGridPositions(shp,fov,ctr)

# create Scanner
robot = IselRobot("/dev/ttyUSB0")
#scanner = MPIScanner("HeadScanner.toml")
scannerSetup = hallSensorRegularScanner

gaussmeter = GaussMeter("/dev/ttyUSB1")
mfMeasObj = MagneticFieldMeas(gaussmeter, u"mT",
               Vector{Vector{typeof(1.0u"m")}}(),Vector{Vector{typeof(1.0u"T")}}())


# Initialize GaussMeter with standard settings
setStandardSettings(mfMeasObj.gaussMeter)
setAllRange(gauss, '1')

res = performTour!(robot, scannerSetup, positions, mfMeasObj)

#move back to park position after measurement has finished
movePark(robot)

saveMagneticFieldAsHDF5(mfMeasObj, "/home/labuser/Desktop/TestBackground.hd5", 0.25u"Tm^-1")
