export deltaSample, hallSensor, mouseAdapter,customPhantom, brukerCoil, mouseCoil, headCoil,ratCoil, clearance,
dSampleRegularScanner, mouseAdapterRegularScanner, dSampleMouseScanner,
mouseAdapterMouseScanner, hallSensorRegularScanner, hallSensorMouseScanner, getValidRobotSetups,
 getValidScannerGeos, getValidObjects, getValidHeadScannerGeos, getValidHeadObjects

# create given geometries
hallSensor = Circle(36.0u"mm", "Hall Sensor");
deltaSample = Circle(10.0u"mm", "Delta sample");
samplePhantom = Rectangle(65.0u"mm",40.0u"mm", "Sample Phantom")
mouseAdapter = Circle(38.0u"mm", "Mouse adapter");
customPhantom = Rectangle(70.0u"mm",70.0u"mm", "Custom Phantom")

# create given scanner diameter
brukerCoil = ScannerGeo(regularBrukerScannerdiameter, "Burker Coil", xMinBrukerRobot, xMaxBrukerRobot);
mouseCoil = ScannerGeo(40.0u"mm", "Mouse Coil", xMinBrukerRobot, xMaxBrukerRobot);
ratCoil = ScannerGeo(72.0u"mm", "Rat Coil", xMinBrukerRobot, xMaxBrukerRobot)
headCoil = ScannerGeo(170.0u"mm", "Head Coil", -65.0u"mm", 365.0u"mm");

# standard clearance
clearance = Clearance(1.0u"mm");

validScannerGeos = [brukerCoil, mouseCoil, ratCoil, headCoil]
validObjects = [deltaSample, hallSensor, mouseAdapter, samplePhantom]

validHeadScannerGeos = [headCoil]
validHeadObjects = [samplePhantom, deltaSample, hallSensor, customPhantom]

# Standard Combination RobotSetup
dSampleRegularScanner = RobotSetup("dSampleRegularScanner", deltaSample, brukerCoil, clearance);
mouseAdapterRegularScanner = RobotSetup("mouseAdapterRegularScanner", mouseAdapter, brukerCoil, clearance);
dSampleMouseScanner = RobotSetup("dSampleMouseScanner", deltaSample, mouseCoil, clearance);
mouseAdapterMouseScanner = RobotSetup("mouseAdapterMouseScanner", mouseAdapter, mouseCoil, clearance);
dSampleRatScanner = RobotSetup("dSampleRatScanner", deltaSample, ratCoil, clearance);
mouseAdapterRatScanner = RobotSetup("mouseAdapterRatScanner", mouseAdapter, ratCoil, clearance);
hallSensorRegularScanner = RobotSetup("hallSensorRegularScanner", hallSensor, brukerCoil, clearance)
hallSensorMouseScanner = RobotSetup("hallSensorMouseScanner", hallSensor, mouseCoil, clearance)
hallSensorRatScanner = RobotSetup("hallSensorMouseScanner", hallSensor, ratCoil, clearance)

validRobotSetups = [dSampleRegularScanner, mouseAdapterRegularScanner, dSampleMouseScanner, mouseAdapterMouseScanner,
 dSampleRatScanner, mouseAdapterRatScanner, hallSensorRegularScanner, hallSensorMouseScanner, hallSensorRatScanner]

 @doc "Returns all validated Scanner Coils!"->
function getValidScannerGeos()
    return validScannerGeos
end

@doc "Returns all validated Objects!"->
function getValidObjects()
   return validObjects
end

 @doc "Returns all validated Robot Setups!"->
function getValidRobotSetups()
    return validRobotSetups
end

 @doc "Returns all validated Head Scanner!"->
function getValidHeadScannerGeos()
    return validHeadScannerGeos
end

@doc "Returns all validated Head Objects!"->
function getValidHeadObjects()
   return validHeadObjects
end
