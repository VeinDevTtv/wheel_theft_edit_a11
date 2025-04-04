# Task 1: Despawning Work Vehicle on Mission Cancel

Added a WORK_VEHICLE variable in client/truckSpawn.lua to track the vehicle.

Modified SpawnTruck to store the vehicle reference.

Created DespawnWorkVehicle to remove the vehicle properly.

Called this function from CancelMission in client/mission.lua.

Added cleanup when the resource stops.

Ensured it only despawns when the player cancels via the NPC.

# Task 2: Implementing ox_target for Interactions

## Replaced key presses (E/H) with ox_target:

**Mission NPCs (Start/Cancel):**

Added network ID tracking.

Created dynamic options based on mission state.

Cleaned up properly when missions end.

**Seller Ped & Crate (Sale/Drop Wheels):**

Added target options with state-based availability.

Ensured proper cleanup.

**Vehicle Wheel Theft:**

Implemented bone-targeting for precise interactions.

Added different options for target vs. non-target vehicles.

Included options for lowering vehicles and finishing theft.

**Truck Interactions (Store/Take Wheels):**

Added target options for storing and retrieving wheels.

Ensured proper cleanup.

# Code Changes Summary

## Files Affected
- `client/client.lua`

## New Functions Added
1. `RegisterTargetVehicleWithOxTarget(vehicle, isTargetVehicle)`
   - Handles vehicle registration with ox_target
   - Adds wheel theft options
   - Manages vehicle cleanup
   - Parameters:
     - vehicle: The target vehicle entity
     - isTargetVehicle: Boolean indicating if it's a mission vehicle

2. `RegisterTruckWithOxTarget(vehicle)`
   - Manages truck registration for wheel storage
   - Handles wheel storage options
   - Parameters:
     - vehicle: The truck entity

## Modified Functions
1. `StartWheelTheft(vehicle)`
   - Added ox_target integration
   - Improved vehicle tracking
   - Enhanced wheel theft process

2. `StopWheelTheft(vehicle)`
   - Added ox_target cleanup
   - Improved vehicle state management
   - Enhanced mission completion handling

3. `BeginWheelLoadingIntoTruck(wheelProp)`
   - Added ox_target integration
   - Improved wheel storage process
   - Enhanced truck interaction

4. `EnableWheelTakeOut()`
   - Added ox_target integration
   - Improved wheel retrieval process
   - Enhanced truck interaction

## New Variables Added
1. `targetVehicleNetIds`
   - Array to track registered target vehicles
   - Used for cleanup and management

2. `truckNetId`
   - Stores the network ID of the current truck
   - Used for truck-specific operations

## Resource Management
- Added comprehensive cleanup in `onResourceStop` handler
- Improved vehicle tracking and deletion
- Enhanced ox_target entity management

## Integration Points
1. ox_target Integration
   - Vehicle registration
   - Wheel theft options
   - Truck storage options
   - Entity cleanup

2. Vehicle Management
   - Improved vehicle state tracking
   - Enhanced cleanup procedures
   - Better mission vehicle handling

## Total Changes
- 4 new functions
- 4 modified functions
- 2 new variables
- 1 new event handler
- Improved resource management
- Enhanced integration with ox_target