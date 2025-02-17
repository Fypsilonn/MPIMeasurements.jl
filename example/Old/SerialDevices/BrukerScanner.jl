using MPIMeasurements
using Unitful

# Create Bruker BaseScanner object
bR = BrukerRobot("RobotServer")

################# Use case 1 Basic Move #######################################

# Move absolue LowLevel no safetyCheck!
movePark(bR)
moveCenter(bR)
getPos(bR)
moveAbs(bR, 1.0Unitful.mm, 0.0Unitful.mm, 0.0Unitful.mm)

# Move absolute MidLevel
posXYZ = [1.0Unitful.mm,0.0Unitful.mm,0.0Unitful.mm]
moveAbs(bS, posXYZ)

################# Use case 2 Move and Measure #################################
