//#define DEBUG_MPDE_FULL
#include <\x\alive\addons\mil_ato\script_component.hpp>
SCRIPT(ATO);

/* ----------------------------------------------------------------------------
Function: ALIVE_fnc_ATO
Description:
Military Air Tasking Orders

Parameters:
Nil or Object - If Nil, return a new instance. If Object, reference an existing instance.
String - The selected function
Array - The selected parameters

Returns:
Any - The new instance or the result of the selected function and parameters

Attributes:
Nil - init - Initiate instance
Nil - destroy - Destroy instance
Boolean - debug - Debug enabled
Array - state - Save and restore module state
Array - faction - Faction associated with module

Examples:
[_logic, "debug", true] call ALiVE_fnc_ATO;

See Also:
- <ALIVE_fnc_ATOInit>
- The Slowest Arma Module Ever Written

Author:
Tupolov
---------------------------------------------------------------------------- */

#define SUPERCLASS ALIVE_fnc_baseClass
#define MAINCLASS ALIVE_fnc_ATO
#define MTEMPLATE "ALiVE_ATO_%1"
#define DEFAULT_FACTION ""
#define DEFAULT_AIRSPACE []
#define DEFAULT_EVENT_QUEUE []
#define DEFAULT_ANALYSIS []
#define DEFAULT_SIDE "EAST"
#define DEFAULT_ATO_TYPES ["CAP","DCA","SEAD","CAS","STRIKE","RECCE"]
#define DEFAULT_REGISTRY_ID ""
#define DEFAULT_OP_HEIGHT 750
#define DEFAULT_OP_DURATION 25
#define DEFAULT_SPEED "NORMAL"
#define DEFAULT_MIN_WEAP_STATE 0.5
#define DEFAULT_MIN_FUEL_STATE 0.5
#define DEFAULT_RADAR_HEIGHT 105
#define WAIT_TIME_CAS 10
#define WAIT_TIME_DCA 30
#define WAIT_TIME_CAP 60
#define WAIT_TIME_SEAD 60
#define WAIT_TIME_STRIKE 90
#define WAIT_TIME_RECCE 90


TRACE_1("ATO - input",_this);

params [
    ["_logic", objNull, [objNull]],
    ["_operation", "", [""]],
    ["_args", objNull, [objNull,[],"",0,true,false]]
];

ALiVE_fnc_catapultLaunch = {
   params [
        ["_vehicle", objNull, [objNull]],
        ["_catapult", [], [[]]]
    ];

    private _result = false;

    private _part = [_catapult, "part",objNull] call ALiVE_fnc_hashGet;
    private _animations = [_catapult, "animations",[]] call ALiVE_fnc_hashGet;
    private _partMemPoint = [_catapult, "memoryPoint",[]] call ALiVE_fnc_hashGet;
    private _catPos = [_catapult, "position",getposASL _vehicle] call ALiVE_fnc_hashGet;
    private _catDir = [_catapult, "dirOffset", direction _part] call ALiVE_fnc_hashGet;
    private _ldir = [(direction _part) + 180 - _catDir] call ALiVE_fnc_modDegrees;
    _vehicle setDir _ldir;
    _vehicle setposASL _catPos;

    if (alive _vehicle && canMove _vehicle) then {

        // Keep the aircraft level until takeoff
        private _vectorUp = [0,0,1];
        [_vehicle, _vectorUp, _ldir] spawn {
           params [
                ["_vehicle", objNull, [objNull]],
                ["_vectorUp", [], [[]]],
                ["_ldir",0,[0]]
            ];
            private _configPath = configFile >> "CfgVehicles" >> typeOf _vehicle;
            private _velocityLaunch = ((_configPath >> "CarrierOpsCompatability" >> "LaunchVelocity") call BIS_fnc_getCfgData) max 270;
            while {speed _vehicle < _velocityLaunch} do {
                // diag_log str(_vectorUp);
                _vehicle setDir _ldir;
                _vehicle setVectorUp _vectorUp;
            };
        };

        // Launch aircraft
        [_part, _animations, _vehicle] spawn {
            params [
                ["_part", objNull, [objNull]],
                ["_animations", [], [[]]],
                ["_vehicle", objNull, [objNull]]
            ];
            [_part, _animations, 10] call BIS_fnc_Carrier01AnimateDeflectors;

            sleep 10;

            _vehicle allowDamage false;

            [_vehicle] call BIS_fnc_AircraftCatapultLaunch;

            sleep 5;

            [_part, _animations, 0] call BIS_fnc_Carrier01AnimateDeflectors;

            _vehicle allowDamage true;
        };

        _result = true;
    } else {
        _result = false;
    };

    _result
};

ALiVE_fnc_getAirportTaxiPos = {
    params [
        ["_airportID", 0, [0]],
        ["_taxiPos", "ilsTaxiIn", [""]], // ilsTaxiIn or ilsTaxisOff
        ["_scope", 0, [0]]
    ];

    private _result = [];

    if (_airportID == 0) then {
        _result = getArray(configFile >> "cfgWorlds" >> WorldName >> _taxiPos);
    };

    if ( (_airportID > 0) && (_airportID < 100) ) then {
        _result = getArray(((configFile >> "cfgWorlds" >> WorldName >> "SecondaryAirports") select (_airportID-1)) >> _taxiPos);
    };

    if (_airportID > 99) then {
        // is a dynamic runway
        private _runway = ALiVE_Carriers select (_airportID - 100);

        _result = getArray(configFile >> "CfgVehicles" >> typeOf _runway >> _taxiPos);
        for "_i" from 0 to (count _result-1) step 2 do {
            private _pos = _runway modelToWorld [(_result select _i), (_result select _i+1), 0];
            _result set [_i, _pos select 0];
            _result set [_i+1, _pos select 1];
        };
    };

    if (_scope != 0) then {
        _result resize _scope;
    };

    _result
};

ALiVE_fnc_getNearestCatapult = {
    params [
        ["_pos", [], [[]]],
        ["_isUCAV", false, [false]]
    ];

    private _result = [];

    private _carrier = nearestObjects [_pos,["StaticShip"],400] select 0;
    if (isNil "_carrier") exitWith {_result};

    private _parts = getArray(configFile >> "CfgVehicles" >> typeof _carrier >> "multiStructureParts");
    if (count _parts == 0) exitWith {_result};

    private _catapults = [] call ALiVE_fnc_hashCreate;
    private _catapultsPos = [];
    {
        private _part = _x select 0;
        if (isClass (configFile >> "CfgVehicles" >> _part >> "Catapults")) then {

            private _tmp = [configFile >> "CfgVehicles" >> _part >> "Catapults"] call ALiVE_fnc_configProperties;

            private _addHash = {
                private _partObject = nearestObjects [_pos,[_part],400] select 0;
                private _partMemPoint = [_value, "memoryPoint"] call ALiVE_fnc_hashGet;
                private _partOffset = _partObject selectionPosition _partMemPoint;
                private _position = _partObject modelToWorld _partOffset;

                // Check to see if object is suitable for Carrier catapults
                if !(_isUCAV && (_partMemPoint == "pos_catapult_01" || _partMemPoint == "pos_catapult_04")) then {
                    _catapultsPos pushback [_key, _position];
                    [_value, "part", _partObject] call ALiVE_fnc_hashSet;
                    [_value, "position", _position] call ALiVE_fnc_hashSet;
                    [_catapults, _key, _value] call ALiVE_fnc_hashSet;
                };
            };

            [_tmp, _addHash] call CBA_fnc_hashEachPair;

        };
    } foreach _parts;

    if (count _catapultsPos == 0) exitWith {_result};

    private _tmp = [
                _catapultsPos,
                [_pos],
                {
                    _Input0 distance (_x select 1);
                },
                "ASCEND"
            ] call ALiVE_fnc_SortBy;

    _result = [_catapults, (_tmp select 0) select 0] call ALiVE_fnc_hashGet;

    _result
};

ALiVE_fnc_isVTOL = {
    params [
        ["_class", "", ["",objNull]]
    ];
    if (typeName _class == "OBJECT") then {_class = typeof _class};

    // vtol 0 = none, 1 = VTOL, 2 = STOVL, 3 = Semi VTOL, 4 = STOSL?
    private _result = getNumber(configFile >> "CfgVehicles" >> _class >> "vtol");
    _result
};


ALiVE_fnc_getAircraftRoles = {
    params [
        ["_class", "", ["",objNull]]
    ];

    if (typeName _class == "OBJECT") then {_class = typeof _class};

    // Attack aircraft have air to surface capability
    // Fighter aircraft have air to air capability
    // Recon aircraft are armed but have surveillance capability?
    // Multi-role aircraft have both attack and fighter
    private _result = [];
    private _cas = false;
    private _recce = false;
    private _attack = false;
    private _fighter = false;

    // Go through weapons and check for guns and cameras
    private _weapons = _class call BIS_fnc_weaponsEntityType;
    {
        if (_x iskindof ["CannonCore", configFile >> "CfgWeapons"]) then {
            _cas = true;
        };
        if (_x iskindof ["Laserdesignator_mounted", configFile >> "CfgWeapons"]) then {
            _recce = true;
        };
    } foreach _weapons;

    // Go through magazines and ammo and check capability for attack (AGM) and fighter (AAM)
    private _magazines = _class call BIS_fnc_magazinesEntityType;
    {

        private _ammoCfg = configFile >> "CfgAmmo" >> (getText(configFile >> "CfgMagazines" >> _x >> "ammo"));
        // Check for AGM and AA missiles
        //if ((configName _ammoCfg) iskindof ["MissileBase", configFile >> "CfgAmmo"]) then {
            private _maxLockSpeed = getNumber(_ammoCfg >> "missileLockMaxSpeed");
            if (_maxLockSpeed > 0) then {
                if (_maxLockSpeed < 150) then {
                    _attack = true;
                    _cas = true;
                } else {
                    _fighter = true;
                };
            };
        //};
    } foreach _magazines;

    if (_cas) then {_result pushback "CAS"};
    if (_recce) then {_result pushback "Recon"};
    if (_attack) then {_result pushback "Attack"};
    if (_fighter) then {_result pushback "Fighter"};

    _result
};

private _result = true;

switch(_operation) do {
    default {
        _result = [_logic, _operation, _args] call SUPERCLASS;
    };

    // Attributes
    case "createMarker": {

        private _position = _args select 0;
        private _side = _args select 1;
        private _text = _args select 2;
        private _radius = _args select 3;

        private _markers = _logic getVariable ["markers", []];

        if(count _markers > 10) then {
            {
                deleteMarker _x;
            } forEach _markers;
            _markers = [];
        };

        private _debugColor = "ColorPink";

        switch(_side) do {
            case "EAST":{
                _debugColor = "ColorRed";
            };
            case "WEST":{
                _debugColor = "ColorBlue";
            };
            case "GUER":{
                _debugColor = "ColorGreen";
            };
            case "CIV":{
                _debugColor = "ColorBrown";
            };
            default {
                _debugColor = "ColorGreen";
            };
        };

        private  _markerID = time;

        if(count _position > 0) then {
            private _m = createMarker [format["%1_%2",MTEMPLATE,_markerID], _position];

            if (_text find "RADIUS" != -1) then {
                _m setMarkerShape "ELLIPSE";
                _m setMarkerSize [_radius,_radius];
                _m setMarkerAlpha 0.3;
            } else {
                _m setMarkerShape "ICON";
                _m setMarkerSize [0.5, 0.5];
                _m setMarkerType "mil_dot";
                _m setMarkerText _text;
            };
            _m setMarkerColor _debugColor;
            _markers pushback _m;
        };

        _logic setVariable ["markers", _markers];
    };
    case "destroy": {
        [_logic, "debug", false] call MAINCLASS;
        if (isServer) then {
            // if server
            _logic setVariable ["super", nil];
            _logic setVariable ["class", nil];
            _logic setVariable ["markers", []];

            [_logic, "destroy"] call SUPERCLASS;
        };
    };
    case "debug": {
        if (typeName _args == "BOOL") then {
            _logic setVariable ["debug", _args];
        } else {
            _args = _logic getVariable ["debug", false];
        };
        if (typeName _args == "STRING") then {
                if(_args == "true") then {_args = true;} else {_args = false;};
                _logic setVariable ["debug", _args];
        };
        ASSERT_TRUE(typeName _args == "BOOL",str _args);

        _result = _args;
    };
    case "createHQ": {
        if (typeName _args == "BOOL") then {
            _logic setVariable ["createHQ", _args];
        } else {
            _args = _logic getVariable ["createHQ", false];
        };
        if (typeName _args == "STRING") then {
            if(_args == "true") then {_args = true;} else {_args = false;};
            _logic setVariable ["createHQ", _args];
        };
        ASSERT_TRUE(typeName _args == "BOOL",str _args);

        _result = _args;
    };
    case "placeAA": {
        if (typeName _args == "BOOL") then {
            _logic setVariable ["placeAA", _args];
        } else {
            _args = _logic getVariable ["placeAA", false];
        };
        if (typeName _args == "STRING") then {
            if(_args == "true") then {_args = true;} else {_args = false;};
            _logic setVariable ["placeAA", _args];
        };
        ASSERT_TRUE(typeName _args == "BOOL",str _args);

        _result = _args;
    };
    case "placeAir": {
        if (typeName _args == "BOOL") then {
            _logic setVariable ["placeAir", _args];
        } else {
            _args = _logic getVariable ["placeAir", false];
        };
        if (typeName _args == "STRING") then {
            if(_args == "true") then {_args = true;} else {_args = false;};
            _logic setVariable ["placeAir", _args];
        };
        ASSERT_TRUE(typeName _args == "BOOL",str _args);

        _result = _args;
    };
    case "persistent": {
        if (typeName _args == "BOOL") then {
            _logic setVariable ["persistent", _args];
        } else {
            _args = _logic getVariable ["persistent", false];
        };
        if (typeName _args == "STRING") then {
                if(_args == "true") then {_args = true;} else {_args = false;};
                _logic setVariable ["persistent", _args];
        };
        ASSERT_TRUE(typeName _args == "BOOL",str _args);

        _result = _args;
    };
    case "pause": {
        if(typeName _args != "BOOL") then {
            // if no new value was provided return current setting
            _args = [_logic,"pause",objNull,false] call ALIVE_fnc_OOsimpleOperation;
        } else {
                // if a new value was provided set groups list
                ASSERT_TRUE(typeName _args == "BOOL",str typeName _args);

                private ["_state"];
                _state = [_logic,"pause",objNull,false] call ALIVE_fnc_OOsimpleOperation;
                if (_state && _args) exitwith {};

                //Set value
                _args = [_logic,"pause",_args,false] call ALIVE_fnc_OOsimpleOperation;
                ["ALiVE Pausing state of %1 instance set to %2!",QMOD(ADDON),_args] call ALiVE_fnc_DumpR;
        };
        _result = _args;
    };
    case "airspace": {
        if(typeName _args == "STRING") then {
            _args = [_args, " ", ""] call CBA_fnc_replace;
            _args = [_args, ","] call CBA_fnc_split;
            if(count _args > 0) then {
                _logic setVariable [_operation, _args];
            };
        };
        if(typeName _args == "ARRAY") then {
            _logic setVariable [_operation, _args];
        };
        _result = _logic getVariable [_operation, DEFAULT_AIRSPACE];
    };
    case "types": {
        if(typeName _args == "STRING") then {
            _logic setVariable [_operation, call compile _args];
        };
        if(typeName _args == "ARRAY") then {
            _logic setVariable [_operation, _args];
        };

        _result = _logic getVariable [_operation, DEFAULT_ATO_TYPES];
    };
    case "side": {
        _result = [_logic,_operation,_args,DEFAULT_SIDE] call ALIVE_fnc_OOsimpleOperation;
    };
    case "HQBuilding": {
        _result = [_logic,_operation,_args,objNull] call ALIVE_fnc_OOsimpleOperation;
    };
    case "currentBase": {
        _result = [_logic,_operation,_args,[]] call ALIVE_fnc_OOsimpleOperation;
    };
    case "faction": {
        _result = [_logic,_operation,_args,DEFAULT_FACTION] call ALIVE_fnc_OOsimpleOperation;
    };
    case "factions": {
        _result = [_logic,_operation,_args,[]] call ALIVE_fnc_OOsimpleOperation;
    };
    case "enemyFactions": {
        _result = [_logic,_operation,_args,[]] call ALIVE_fnc_OOsimpleOperation;
    };
    case "registryID": {
        _result = [_logic,_operation,_args,DEFAULT_REGISTRY_ID] call ALIVE_fnc_OOsimpleOperation;
    };
    case "isCarrier": {
        if (typeName _args == "BOOL") then {
            _logic setVariable ["isCarrier", _args];
        } else {
            _args = _logic getVariable ["isCarrier", false];
        };
        if (typeName _args == "STRING") then {
            if(_args == "true") then {_args = true;} else {_args = false;};
            _logic setVariable ["isCarrier", _args];
        };
        ASSERT_TRUE(typeName _args == "BOOL",str _args);

        _result = _args;
    };
    case "assets": {
        _result = [_logic,_operation,_args,[]] call ALIVE_fnc_OOsimpleOperation;
    };
    case "eventQueue": {
        _result = [_logic,_operation,_args,DEFAULT_EVENT_QUEUE] call ALIVE_fnc_OOsimpleOperation;
    };
    case "airspaceAssets": {
        _result = [_logic,_operation,_args,[]] call ALIVE_fnc_OOsimpleOperation;
    };
    case "airspaceOps": {
        _result = [];
        if (typeName _args == "STRING") then {
            // Get ops for the airspace
            private _eventQueue = [_logic, "eventQueue"] call MAINCLASS;
            {
                private _eventData = [_x,"data"] call ALiVE_fnc_hashGet;
                if ((_eventData select 3) == _args) then {
                    _result pushback _eventData;
                };
            } foreach (_eventQueue select 2);
        };
    };

    // Methods
    case "scanAirspace": {

        private _airspace = [_logic,"airspace"] call MAINCLASS;
        private _intruders = [] call ALIVE_fnc_hashCreate;

        // Scan all enemy faction profiles to see if they are in the airspace
        private _enemyFactions = [_logic,"enemyFactions"] call MAINCLASS;
        {
            private _bogey = _x;
            if (faction _bogey in _enemyFactions && (getposATL _bogey) select 2 > DEFAULT_RADAR_HEIGHT) then {
                {
                    if ((getposATL _bogey) inArea _x) then {
                        private _tmp = [_intruders, _x, []] call ALiVE_fnc_hashGet;
                        // diag_log format["Adding to %1 in %2 for %3",_bogey,_tmp,_intruders];
                        _tmp pushback _bogey;
                        [_intruders, _x, _tmp] call ALiVE_fnc_hashSet;
                    };
                } foreach _airspace;
            };
        } foreach vehicles;

        _result = _intruders;
    };
    case "requestAnalysis": {
        _result = [_logic,_operation,_args,DEFAULT_ANALYSIS] call ALIVE_fnc_OOsimpleOperation;
    };
    case "addRunway": {
        private _runways = [_logic,"runways"] call MAINCLASS;
        private _runway = _args;

        if !([_runways,_runway] call CBA_fnc_hashHasKey) then {
            [_runways, _runway, false] call ALIVE_fnc_hashSet;
            [_logic,"runways",_runways] call MAINCLASS;
        };
    };
    case "unlockRunway": {
        private _runways = [_logic,"runways"] call MAINCLASS;
        private _runway = _args;

        if ([_runways,_runway] call CBA_fnc_hashHasKey) then {
            [_runways, _runway, false] call ALIVE_fnc_hashSet;
            [_logic,"runways",_runways] call MAINCLASS;
        };
    };
    case "runways": {
        _result = [_logic,_operation,_args,[]] call ALIVE_fnc_OOsimpleOperation;
    };
    case "registerProfile": {

        // Register an entity or vehicle profile with ATO.
        private _profileID = _args select 0;
        private _assetAirspace = _args select 1;

        private _assets = [_logic,"assets"] call MAINCLASS;

        private _as = [_logic,"airspaceAssets"] call MAINCLASS;
        private _airspaceAssets = [_as, _assetAirspace,[]] call ALiVE_fnc_hashGet;

        private _profile = [ALiVE_ProfileHandler,'getProfile',_profileID] call ALiVE_fnc_ProfileHandler;
        private _vehicleProfileIDs = [_profileID]; // assume its a vehicle profile

        // If this is an entity, then get all vehicles and register them
        private _type = [_profile,"type"] call ALIVE_fnc_hashGet;
        if (_type == "entity") then {
            _vehicleProfileIDs = [_profile, "vehiclesInCommandOf"] call ALiVE_fnc_hashGet;
        };

        {
            private _vehicleProfile = [ALiVE_ProfileHandler,'getProfile',_x] call ALiVE_fnc_ProfileHandler;
            private _vehicleClass = [_vehicleProfile,"vehicleClass",""] call ALIVE_fnc_HashGet;
            private _isVTOL = [_vehicleClass] call ALiVE_fnc_isVTOL;

            // If Combat support asset, then do not register
            private _isCombatSupport = false;
            private _isPlayer = false;
            if ([_vehicleProfile,"active",false] call ALiVE_fnc_hashGet) then {

                private _vehicle = [_vehicleProfile,"vehicle"] call ALiVE_fnc_hashGet;
                private _isCombatSupport = _vehicle getVariable ["ALIVE_CombatSupport", false];
            };
            if (_isCombatSupport) exitWith {

                if (_debug) then {
                    ["ALIVE ATO %1 ignoring %2 as it is a combat support asset", _logic, _vehicleClass] call ALiVE_fnc_dump;
                };

            };

            if ([_vehicleClass] call ALiVE_fnc_isArmed) then {

                // make sure vehicle is set to side of logic
                [_vehicleProfile, "side", [_logic,"side"] call MAINCLASS] call ALiVE_fnc_profileVehicle;

                private _asset = [] call ALIVE_fnc_hashCreate;
                [_asset,"vehicleClass",_vehicleClass] call ALiVE_fnc_hashSet;
                [_asset,"airspace",_assetAirspace] call ALiVE_fnc_hashSet;

                private _position = +([_vehicleProfile,"position"] call ALIVE_fnc_HashGet);
                [_asset,"startPos",_position] call ALiVE_fnc_hashSet;

                private _dir = [_vehicleProfile,"direction"] call ALIVE_fnc_HashGet;
                [_asset,"startDir",_dir] call ALiVE_fnc_hashSet;

                private _isOnCarrier = false;

                if ( [_position] call ALiVE_fnc_nearShip ) then {
                    _isOnCarrier = true;

                    // Due to issues spawning aircraft on ships after changing sea levels keep assets spawned
                    [_vehicleProfile,"spawnType",["preventDespawn"]] call ALiVE_fnc_profileVehicle;
                    [_vehicleProfile,"spawn"] call ALiVE_fnc_profileVehicle;
                };

                [_asset,"isOnCarrier", _isOnCarrier] call ALiVE_fnc_hashSet;

                if (_vehicleClass iskindof "Plane" && ((_isVTOL mod 2) == 0) ) then {

                    // Get airportID
                    private _airportID = [_position] call ALiVE_fnc_getNearestAirportID;
                    [_asset,"airportID",_airportID] call ALiVE_fnc_hashSet;
                    [_logic,"addRunway",_airportID] call MAINCLASS;

                } else {

                    // Heli or VTOL?
                    // Get HeliH object
                    private _helipad = nearestObject [_position, "HeliH"];
                    if (isNull _helipad) then {
                        // create an invisble helipad
                        _helipad = "Land_HelipadEmpty_F" createvehicle _position;
                    };
                    [_asset,"helipad",_helipad] call ALiVE_fnc_hashSet;

                };

                // Check role of aircraft
                private _roles = [_vehicleClass] call ALiVE_fnc_getAircraftRoles;
                [_asset,"roles",_roles] call ALiVE_fnc_hashSet;

                if (_type == "entity") then {

                    [_asset,"crewID",_profileID] call ALiVE_fnc_hashSet;
                    // Set the entity as busy so OPCOM doesn't use it
                    [_profile,"busy",true] call ALIVE_fnc_profileEntity;

                } else {

                    // Register a crew
                    // Check to see if this is just a vehicle (likely a plane), if so create the crew in a nearby building
                    if ([_profile,"type"] call ALiVE_fnc_hashGet == "vehicle" && !(_vehicleClass iskindof "UAV")) then {

                        // Check to see if the vehicle has a crew, if not create
                        if (count ([_profile,"entitiesInCommandOf"] call ALiVE_fnc_hashGet) == 0) then {

                            private _side = [_profile,"side"] call ALiVE_fnc_hashGet;
                            private _faction = [_profile,"faction"] call ALiVE_fnc_hashGet;
                            private _crewpos = +_position;

                            // Get nearest building position
                            if !(_isOnCarrier) then {
                                _crewPos = selectRandom ((nearestBuilding _position) buildingPos -1);
                            } else {
                                private _bridge = (_position nearObjects ["Land_Carrier_01_island_02_F",700]) select 0;
                                _crewPos = ASLtoATL (_bridge modelToWorld [-2.43359,1.98047,0]); // entities are saved as ATL positions
                                // ["ALIVE ATO PLACE CREW AT %1 (pos: %2)", _crewpos, _position] call ALiVE_fnc_dump;
                            };

                            // Check for no building?

                            private _entityID = [ALIVE_profileHandler, "getNextInsertEntityID"] call ALIVE_fnc_profileHandler;
                            private _profileEntity = [nil, "create"] call ALIVE_fnc_profileEntity;
                            [_profileEntity, "init"] call ALIVE_fnc_profileEntity;
                            [_profileEntity, "profileID", format["%1-%2",_faction,_entityID]] call ALIVE_fnc_profileEntity;
                            [_profileEntity, "position", _crewPos] call ALIVE_fnc_profileEntity;
                            [_profileEntity, "side", _side] call ALIVE_fnc_profileEntity;
                            [_profileEntity, "faction", _faction] call ALIVE_fnc_profileEntity;
                            [_profileEntity, "busy", true] call ALIVE_fnc_profileEntity;

                            [_profileEntity, "despawnPosition", _crewPos] call ALIVE_fnc_profileEntity;

                            [ALIVE_profileHandler, "registerProfile", _profileEntity] call ALIVE_fnc_profileHandler;

                            // Create the vehicle's crew
                            private _crew = _vehicleClass call ALIVE_fnc_configGetVehicleCrew;
                            private _vehiclePositions = [_vehicleClass] call ALIVE_fnc_configGetVehicleEmptyPositions;
                            private _countCrewPositions = 0;

                            // count all non cargo positions
                            for "_i" from 0 to count _vehiclePositions -3 do {
                                _countCrewPositions = _countCrewPositions + (_vehiclePositions select _i);
                            };

                            // for all crew positions add units to the entity group
                            for "_i" from 0 to _countCrewPositions -1 do {
                                [_profileEntity, "addUnit", [_crew,_crewPos,0,"CAPTAIN"]] call ALIVE_fnc_profileEntity;
                            };

                            // Store the crew as a profileID
                            [_asset,"crewID",([_profileEntity, "profileID"] call ALIVE_fnc_profileEntity)] call ALiVE_fnc_hashSet;
                        };
                    };
                };

                // Register asset
                [_assets,_x,_asset] call ALiVE_fnc_hashSet;

                // Register asset in airspace
                _airspaceAssets pushback _x;

                if (_debug) then {
                    ["ALIVE ATO %1 registered %2 (%3) as an asset.", _logic, _x, _vehicleClass] call ALIVE_fnc_dump;
                };

            } else {
                if (_debug) then {
                    ["ALIVE ATO %1 not registering %2 (%3) as it is unarmed.", _logic, _x, _vehicleClass] call ALIVE_fnc_dump;
                };
            };
        } foreach _vehicleProfileIDs;

        // Set assets
        [_logic,"assets",_assets] call MAINCLASS;

        // Set airspace
        [_as, _assetAirspace, _airspaceAssets] call ALIVE_fnc_hashSet;
        [_logic,"airspaceAssets", _as] call MAINCLASS;
    };

    // Main process
    // Set module variables and attributes
    case "init": {
        if (isServer) then {

            // if server, initialise module game logic
            _logic setVariable ["super", SUPERCLASS];
            _logic setVariable ["class", MAINCLASS];
            _logic setVariable ["moduleType", "ALIVE_ATO"];
            _logic setVariable ["startupComplete", false];
            _logic setVariable ["listenerID", ""];
            _logic setVariable ["registryID", ""];
            _logic setVariable ["initialAnalysisComplete", false];
            _logic setVariable ["analysisInProgress", false];
            _logic setVariable ["eventQueue", [] call ALIVE_fnc_hashCreate];
            _logic setVariable ["position", getposATL _logic];

            private _debug = [_logic, "debug"] call MAINCLASS;
            private _faction = [_logic, "faction"] call MAINCLASS;

            private _side = _faction call ALiVE_fnc_factionSide;
            [_logic, "side", str _side] call MAINCLASS;

            private _factions = [_logic, "factions",[_faction]] call MAINCLASS;
            private _types = [_logic, "types", _logic getVariable ["types", DEFAULT_ATO_TYPES]] call MAINCLASS;
            private _airspace = [_logic, "airspace", _logic getVariable ["airspace", DEFAULT_AIRSPACE]] call MAINCLASS;
            [_logic,"assets",[] call ALiVE_fnc_hashCreate] call MAINCLASS;
            [_logic,"airspaceAssets",[] call ALiVE_fnc_hashCreate] call MAINCLASS;
            [_logic,"runways",[] call ALiVE_fnc_hashCreate] call MAINCLASS;

            // Define enemy factions by getting enemy sides
            private _enemyFactions = [];
            private _sides = ["EAST","WEST","RESISTANCE"];
            private _sidesEnemy = [];

            {
                if ((_side getfriend (call compile _x)) < 0.6) then {
                    _sidesEnemy pushBack _x
                };
            } foreach (_sides - [_side]);

            //Thank you again, BIS...
            {if (_x == "RESISTANCE") then {_sidesEnemy set [_foreachIndex,"GUER"]}} foreach _sidesEnemy;

            {
                // Get side factions
                _enemyFactions append (_x call ALiVE_fnc_getSideFactions);
            } foreach _sidesEnemy;

            [_logic,"enemyFactions",_enemyFactions] call MAINCLASS;

            // If no airspace marker, then use the whole map
            if (count _airspace == 0) then {
                private _marker = createMarker [format["ATO_%1", ceil(random 10000)], [worldSize/2,worldSize/2]];
                _marker setMarkerSize [worldSize/2 - 100,worldSize/2 - 100];
                _marker setMarkerShape "RECTANGLE";
                // _marker setMarkerColor "colorBlue";
                _marker setMarkerAlpha 0;
                [_logic, "airspace", [_marker]] call MAINCLASS;
            };

            // DEBUG -------------------------------------------------------------------------------------
            if(_debug) then {
                ["----------------------------------------------------------------------------------------"] call ALIVE_fnc_dump;
                ["ALIVE ATO - Init %1", _logic] call ALIVE_fnc_dump;
                ["ALIVE ATO - ATO Types: %1",[_logic, "types"] call MAINCLASS] call ALIVE_fnc_dump;
                ["ALIVE ATO - Airspace Markers: %1",[_logic, "airspace"] call MAINCLASS] call ALIVE_fnc_dump;
                ["ALIVE ATO - Side: %1",[_logic, "side"] call MAINCLASS] call ALIVE_fnc_dump;
                ["ALIVE ATO - Factions: %1",[_logic, "factions"] call MAINCLASS] call ALIVE_fnc_dump;
                ["ALIVE ATO - Create HQ: %1",[_logic, "createHQ"] call MAINCLASS] call ALIVE_fnc_dump;
                ["ALIVE ATO - Place Anti-Air: %1",[_logic, "placeAA"] call MAINCLASS] call ALIVE_fnc_dump;
                ["ALIVE ATO - Place Air Assets: %1",[_logic, "placeAir"] call MAINCLASS] call ALIVE_fnc_dump;
            };
            // DEBUG -------------------------------------------------------------------------------------

            // create the global registry
            if(isNil "ALIVE_ATOGlobalRegistry") then {
                ALIVE_ATOGlobalRegistry = [nil, "create"] call ALIVE_fnc_ATOGlobalRegistry;
                [ALIVE_ATOGlobalRegistry, "init"] call ALIVE_fnc_ATOGlobalRegistry;
                [ALIVE_ATOGlobalRegistry, "debug", _debug] call ALIVE_fnc_ATOGlobalRegistry;
            };

            TRACE_1("After module init",_logic);

            [_logic,"start"] call MAINCLASS;
        } else {
            // Make any markers invisible
            [_logic, "airspace", _logic getVariable ["airspace", DEFAULT_AIRSPACE]] call MAINCLASS;
            {_x setMarkerAlpha 0} foreach (_logic getVariable ["airspace", DEFAULT_AIRSPACE]);
        };
    };

    // Analyse synchronised OPCOMs, create HQ, create AA, set HQ base cluster
    case "start": {
        if (isServer) then {

            private ["_modules","_module","_worldName","_file","_moduleObject"];

            private _debug = [_logic, "debug"] call MAINCLASS;
            private _isCarrier = false;

            // DEBUG -------------------------------------------------------------------------------------
            if(_debug) then {
                ["----------------------------------------------------------------------------------------"] call ALIVE_fnc_dump;
                ["ALIVE ATO %1 - Startup", _logic] call ALIVE_fnc_dump;
            };
            // DEBUG -------------------------------------------------------------------------------------

            // check modules are available
            if !(["ALiVE_sys_profile","ALiVE_mil_opcom"] call ALiVE_fnc_isModuleAvailable) exitwith {
                ["Military air tasking orders reports that Virtual AI module or OPCOM is not placed! Exiting..."] call ALiVE_fnc_DumpR;
            };
            waituntil {!(isnil "ALiVE_ProfileHandler") && {[ALiVE_ProfileSystem,"startupComplete",false] call ALIVE_fnc_hashGet}};

            // if civ cluster data not loaded, load it
            if(isNil "ALIVE_clustersCiv" && isNil "ALIVE_loadedCivClusters") then {
                _worldName = toLower(worldName);
                _file = format["x\alive\addons\civ_placement\clusters\clusters.%1_civ.sqf", _worldName];
                call compile preprocessFileLineNumbers _file;
                ALIVE_loadedCIVClusters = true;
            };
            waituntil {!(isnil "ALIVE_loadedCIVClusters") && {ALIVE_loadedCIVClusters}};

            // if mil cluster data not loaded, load it
            if(isNil "ALIVE_clustersMil" && isNil "ALIVE_loadedMilClusters") then {
                _worldName = toLower(worldName);
                _file = format["x\alive\addons\mil_placement\clusters\clusters.%1_mil.sqf", _worldName];
                call compile preprocessFileLineNumbers _file;
                ALIVE_loadedMilClusters = true;
            };
            waituntil {!(isnil "ALIVE_loadedMilClusters") && {ALIVE_loadedMilClusters}};

            // get all synced modules
            _modules = [];
            for "_i" from 0 to ((count synchronizedObjects _logic)-1) do {
                _moduleObject = (synchronizedObjects _logic) select _i;

                waituntil {_module = _moduleObject getVariable "handler"; !(isnil "_module")};
                _module = _moduleObject getVariable "handler";
                _modules pushback _module;
            };

            // Establish base of operations for ATO
            // Find plane related clusters on map
            private _airspace = [_logic, "airspace"] call MAINCLASS;
            private _airClusters = [(ALIVE_clustersMilAir select 2), _airspace] call ALIVE_fnc_clustersInsideMarker;

            // If no runways etc then look for helipads
            if (count _airClusters == 0) then {
                _airClusters = [(ALIVE_clustersMilHeli select 2), _airspace] call ALIVE_fnc_clustersInsideMarker;
            };

            // Select the nearest cluster to the module or use Aircraft Carrier
            private _position = getposATL _logic;

            // Check for Carrier, if so, create base cluster around Carrier
            if ([_position] call ALiVE_fnc_nearShip) then {
                _isCarrier = true;
            };

            // Sort clusters by distance
            private _tmp = [_airclusters,[_position],{_Input0 distance ([_x,"center",[0,0,0]] call ALiVE_fnc_HashGet)},"ASCEND"] call ALiVE_fnc_SortBy;
            private _baseCluster = _tmp select 0;

            // Always use the carrier as the base if the module is close to the carrier
            if (_isCarrier) then {
                _baseCluster = ([(AGLtoASL _position) nearObjects ["Strategic",700]] call ALiVE_fnc_findClusters) select 0;
                [_baseCluster,"center", [[_baseCluster,"nodes"] call ALiVE_fnc_hashGet] call ALiVE_fnc_findClusterCenter] call ALiVE_fnc_hashSet;
                [_baseCluster,"size",[_baseCluster,"size"] call ALiVE_fnc_cluster] call ALiVE_fnc_hashSet;
            };

            if (_debug) then {
                ["Nearest Base Cluster %1 --------------------------------------------------------------------------", _logic] call ALIVE_fnc_dump;
                _baseCluster call ALIVE_fnc_inspectHash;
            };

            // If createHQ, select a suitable nearby building or create one, if not, choose a building or just use node
            private _createHQ = [_logic, "createHQ"] call MAINCLASS;
            If (_createHQ && !_isCarrier) then {

                private _faction = [_logic, "faction"] call MAINCLASS;

                // Get nearest buildings
                private _buildings = nearestObjects [_position, ["building"], 750];

                // Check for water, spawn carrier?


                // Check to see if the buildings match our ALiVE types
                {
                    private _blg = typeof _x;
                    if ( {(tolower _blg) find (tolower _x) != -1} count (ALiVE_militaryBuildingTypes + ALIVE_militaryHQBuildingTypes) == 0) then {
                        _buildings set [_forEachIndex, -1];
                    };
                    if !([_x] call ALIVE_fnc_isHouseEnterable) then {
                        _buildings set [_forEachIndex, -1];
                    };
                } foreach _buildings;
                _buildings = _buildings - [-1];

                // ["ALIVE ATO %1 - Buildings: %2", _logic, _buildings] call ALIVE_fnc_dump;
                if(count _buildings > 0) then {
                    private _hqBuilding = _buildings select 0;


                    // DEBUG -------------------------------------------------------------------------------------
                    if(_debug) then {
                        [position _hqBuilding, 4] call ALIVE_fnc_placeDebugMarker;
                    };
                    // DEBUG -------------------------------------------------------------------------------------

                    private _group = ["Infantry",_faction] call ALIVE_fnc_configGetRandomGroup;
                    private _profiles = [_group, position _hqBuilding, random 360, true, _faction] call ALIVE_fnc_createProfilesFromGroupConfig;

                    {
                        if (([_x,"type"] call ALiVE_fnc_HashGet) == "entity") then {
                            [_x, "setActiveCommand", ["ALIVE_fnc_garrison","spawn",[50,"false",[0,0,0]]]] call ALIVE_fnc_profileEntity;
                        };
                    } foreach _profiles;

                    [_logic, "HQBuilding", _hqBuilding] call MAINCLASS;

                    if (_debug) then {
                        ["ALIVE ATO %1 - ATO building selected: %2", _logic, [_logic, "HQBuilding"] call MAINCLASS] call ALIVE_fnc_dump;
                    };

                } else {

                    // Spawn a field HQ
                    private _pos = [_baseCluster,"center"] call ALiVE_fnc_HashGet;
                    private _size = [_baseCluster,"size",150] call ALiVE_fnc_HashGet;
                    private _HQ = nil;
                    private _flatPos = [_pos,_size,45] call ALiVE_fnc_findFlatArea;

                    if (isNil QMOD(COMPOSITIONS_LOADED)) then {

                        // Get a composition
                        private _compType = "Military";
                        If (_faction call ALiVE_fnc_factionSide == RESISTANCE) then {
                            _compType = "Guerrilla";
                        };
                        _HQ = selectRandom ([_compType, ["Airports","Heliports"], [], _faction] call ALiVE_fnc_getCompositions);

                        if (isNil "_HQ") then {
                            _HQ = selectRandom ([_compType, ["HQ","FieldHQ","Communications"], ["Medium"], _faction] call ALiVE_fnc_getCompositions);
                        };

                        private _nearRoad = [_flatpos, 750, true] call ALiVE_fnc_getClosestRoad;

                        private _direction = if (_nearRoad distance _flatpos > 5) then {
                            private _road = roadat _nearRoad;
                            private _roadConnectedTo = roadsConnectedTo _road;
                            if (count _roadConnectedTo > 0) then {
                                private _connectedRoad = _roadConnectedTo select 0;
                                (_road getDir _connectedRoad)
                            } else {
                                90
                            };
                        } else {
                            0
                        };

                        // [_logic,"createMarker",[_nearRoad,"WEST","HQ " + str(_direction),0]] call MAINCLASS;

                        [_HQ, _flatPos, _direction, _faction] call ALiVE_fnc_spawnComposition;
                    };

                    [_logic, "HQBuilding", nearestObject [_flatPos, "building"]] call MAINCLASS;

                    if !(ALIVE_loadProfilesPersistent) then {
                        private _group = ["Infantry",_faction] call ALIVE_fnc_configGetRandomGroup;
                        private _profiles = [_group, _flatPos, random 360, true, _faction] call ALIVE_fnc_createProfilesFromGroupConfig;

                        {
                            if (([_x,"type"] call ALiVE_fnc_HashGet) == "entity") then {
                                [_x, "setActiveCommand", ["ALIVE_fnc_garrison","spawn",[50,"false",[0,0,0]]]] call ALIVE_fnc_profileEntity;
                            };
                        } foreach _profiles;
                    };

                    // DEBUG -------------------------------------------------------------------------------------
                    if(_debug) then {
                        [_flatPos, 4] call ALIVE_fnc_placeDebugMarker;

                        ["ALIVE ATO %1 - Field ATO created: %2 - %3", _logic, configName _HQ, [_logic, "HQBuilding"] call MAINCLASS] call ALIVE_fnc_dump;
                    };
                    // DEBUG -------------------------------------------------------------------------------------
                };
            } else {
                private _faction = [_logic, "faction"] call MAINCLASS;

                // Get nearest buildings
                private _buildings = nearestObjects [_position, ["building"], 750];
                private _hqBuilding = objnull;

                // Check for water, spawn carrier?


                // Check to see if the buildings match our ALiVE types
                {
                    private _blg = typeof _x;
                    if ( {(tolower _blg) find (tolower _x) != -1} count (ALiVE_militaryBuildingTypes + ALIVE_militaryHQBuildingTypes) == 0) then {
                        _buildings set [_forEachIndex, -1];
                    };
                    if !([_x] call ALIVE_fnc_isHouseEnterable) then {
                        _buildings set [_forEachIndex, -1];
                    };
                } foreach _buildings;
                _buildings = _buildings - [-1];

                // ["ALIVE ATO %1 - Buildings: %2", _logic, _buildings] call ALIVE_fnc_dump;
                if(count _buildings > 0) then {

                    _hqBuilding = _buildings select 0;

                } else {

                    _hqBuilding = ([_baseCluster,"nodes"] call ALiVE_fnc_hashGet) select 0;

                };

                // DEBUG -------------------------------------------------------------------------------------
                if(_debug) then {
                    [position _hqBuilding, 4] call ALIVE_fnc_placeDebugMarker;
                };
                // DEBUG -------------------------------------------------------------------------------------

                [_logic, "HQBuilding", _hqBuilding] call MAINCLASS;

                if (_debug) then {
                    ["ALIVE ATO %1 - ATO building selected: %2", _logic, [_logic, "HQBuilding"] call MAINCLASS] call ALIVE_fnc_dump;
                };
            };

            // Establish Anti-Air Defenses
            private _placeAA = [_logic, "placeAA"] call MAINCLASS;
            If (_placeAA) then {
                // Dedicated AA protecting your ATO base
            };

            // Set the base location
            [_logic,"currentBase", _baseCluster] call MAINCLASS;

            if(count _modules > 0 && !_isCarrier) then {
                // Tell OPCOM this is a high priority reserve objective
                private _opcom = selectRandom _modules;
                private _id = format["OPCOM_%1_objective_%2",[_opcom,"opcomID"] call ALiVE_fnc_hashGet, format["ATO_%1",ceil(random 1000)]];
                private _pos = [_baseCluster, "center"] call ALiVE_fnc_hashGet;
                private _size = [_baseCluster, "size"] call ALiVE_fnc_hashGet;
                private _type = "strategic";
                private _priority = 500;
                private _opcom_state = "unassigned";
                private _clusterID = [_baseCluster, "clusterID"] call ALiVE_fnc_hashGet;
                private _opcomID = [_opcom,"opcomID"] call ALiVE_fnc_hashGet;

                [_opcom,"addObjective",[_id,_pos,_size,_type,_priority,_opcom_state,_clusterID,_opcomID]] call ALiVE_fnc_OPCOM;
            };

            // DEBUG -------------------------------------------------------------------------------------
            if(_debug) then {
                ["ALIVE ATO %1 - Startup completed", _logic] call ALIVE_fnc_dump;
                ["----------------------------------------------------------------------------------------"] call ALIVE_fnc_dump;
            };
            // DEBUG -------------------------------------------------------------------------------------

            _logic setVariable ["startupComplete", true];

            [_logic,"isCarrier", _isCarrier] call MAINCLASS;

            if(count _modules > 0) then {

                // start initial analysis
                [_logic, "initialAnalysis", _modules] call MAINCLASS;
            }else{
                ["ALIVE ATO %1 - Information no OPCOM modules synced to Military air tasking orders module. No CAS, Strike or Recce ATOs will be available", _logic] call ALIVE_fnc_dump;

            };
        };
    };

    // Analyse Air assets, place aircraft if needed
    case "initialAnalysis": {

        // Get the OPCOMs synchronized and register all air assets and airbases

        if (isServer) then {

            private _modules = _args;
            private _debug = [_logic, "debug"] call MAINCLASS;
            private _modulesFactions = [_logic, "factions"] call MAINCLASS;
            private _airspace = [_logic, "airspace"] call MAINCLASS;
            private _isCarrier = [_logic, "isCarrier"] call MAINCLASS;

            private _modulesAir = [];
            private _opcoms =[];

            // get modules settings and air assets from syncronised OPCOM instances -------------------------------------------------------------------
            {
                private _module = _x;

                waituntil {
                    ["ALiVE ATO %1 waiting for OPCOM %2", _logic, [_module,"module"] call ALIVE_fnc_hashGet] call ALiVE_fnc_dump;
                    sleep 10;
                    [_module, "startupComplete"] call ALiVE_fnc_hashGet;
                };

                private _moduleSide = [_module,"side"] call ALiVE_fnc_HashGet;

                // If OPCOM isn't friendly don't add them
                if !([[_moduleSide] call ALIVE_fnc_sideTextToObject,[[_logic, "side"] call MAINCLASS] call ALIVE_fnc_sideTextToObject] call BIS_fnc_sideIsFriendly) exitWith {
                    ["ALIVE ATO %1 - Warning, you synced an OPCOM to an ATO that is not side friendly.", _logic] call ALIVE_fnc_dumpR;
                    _modules deleteAt _forEachIndex;
                };

                // Register side with clients
                MOD(Require) setVariable [format["ALIVE_MIL_ATO_AVAIL_%1", _moduleSide], true, true];

                // Register factions from OPCOM
                private _moduleFactions = [_module,"factions"] call ALiVE_fnc_HashGet;
                {
                    if !(_x in _modulesfactions) then {
                        _modulesFactions pushback _x;
                    };
                } foreach _moduleFactions;

                // Get an initial list of air assets from OPCOM
                private _moduleAir = [_module,"air",[]] call ALiVE_fnc_HashGet;
                _modulesAir append _moduleAir;

                if (_debug) then {
                    ["ALIVE ATO %1 OPCOM registered air assets: %2", _logic, _moduleAir] call ALiVE_fnc_dump;
                };

                // Get objectives?
                private _objectives = [_module,"objectives"] call ALiVE_fnc_hashGet;
                // (_objectives select 0) call ALIVE_fnc_inspectHash;
            } forEach _modules;

            [_logic, "factions", _modulesFactions] call MAINCLASS;

            // Check for any uncrewed profiled vehicles (not registered with OPCOMs) -----------------------------------------------------
            private _profileIDs = [];
            {
                _profileIDs = _profileIDs + ([ALIVE_profileHandler, "getProfilesByFaction",_x] call ALIVE_fnc_profileHandler);
            } foreach _modulesFactions;

            {
                private _profile = [ALIVE_profileHandler, "getProfile",_x] call ALIVE_fnc_profileHandler;

                if !(isnil "_profile") then {

                    private _type = [_profile,"type"] call ALIVE_fnc_hashGet;

                    switch (tolower _type) do {
                        case ("vehicle") : {

                            private _assignments = [_profile,"entitiesInCommandOf",[]] call ALIVE_fnc_hashGet;

                            if ((count (_assignments)) == 0) then {
                                private _objectType = [_profile,"objectType"] call ALIVE_fnc_hashGet;
                                if (tolower _objectType == "plane" || tolower _objectType == "helicopter") then {
                                        _modulesAir pushback _x;
                                };
                            };
                        };
                    };
                };
            } foreach _profileIDs;

            if (_debug) then {
                    ["ALIVE ATO %1 OPCOM overall air assets: %2", _logic, _modulesAir] call ALiVE_fnc_dump;
            };

            // Go through all profiles and register them ---------------------------------------------------------------------------------------------------
            {
                private _profileID = _x;
                private _profile = [ALIVE_profileHandler, "getProfile",_profileID] call ALIVE_fnc_profileHandler;
                if !(isnil "_profile") then {

                    private _position = [_profile,"position"] call ALIVE_fnc_hashGet;

                    // Check to see if asset is in an airspace
                    private _assetAirspace = nil;
                    {
                        if (_position inArea _x) exitWith {
                            _assetAirspace = _x;
                        };
                    } foreach _airspace;

                    if !(isNil "_assetAirspace") then {
                        [_logic,"registerProfile",[_profileID, _assetAirspace]] call MAINCLASS;
                    };
                };
            } foreach _modulesAir;


            // If there are no armed air assets and place Air is true then place at least one armed plane or heli ------------------------------------
            private _placeAir = [_logic, "placeAir"] call MAINCLASS;
            private _airCount = [_logic,"assets"] call MAINCLASS;

            if (_debug) then {
                ["ALIVE ATO %1 AIR ASSETS: %2",_logic, _airCount] call ALiVE_fnc_dump;
            };

            // Don't place aircraft on carrier
            if (count (_airCount select 1) < 2 && _placeAir && !_isCarrier) then {

                if(_debug) then {
                    ["ALIVE ATO %1 - No armed air assets available, placing additional aircraft at base location", _logic] call ALIVE_fnc_dump;
                };

                private _baseCluster = [_logic, "currentBase"] call MAINCLASS;
                private _center = [_baseCluster,"center"] call ALiVE_fnc_hashGet;
                // [_baseCluster, "debug", true] call ALIVE_fnc_cluster;

                // Set airspace where base and assets are located
                private _baseAirspace = _airspace select 0;
                {
                    if (_center inArea _x) exitWith {
                        _baseAirspace = _x;
                    };
                } foreach _airspace;

                private _side = [_logic, "side"] call MAINCLASS;
                private _faction = [_logic, "faction"] call MAINCLASS;
                private _profiles = [];

                // Place Helis
                private _heliClasses = [0,_faction,"Helicopter"] call ALiVE_fnc_findVehicleType;
                _heliClasses = _heliClasses - ALiVE_PLACEMENT_VEHICLEBLACKLIST;

                // Remove unarmed classes
                {
                    if !([_x] call ALiVE_fnc_isArmed) then {
                        _heliClasses set [_forEachIndex, -1];
                    };
                } foreach _heliClasses;

                _heliClasses = _heliClasses - [-1];

                if(count _heliClasses > 0) then {
                    private _nodes = [_baseCluster, "nodes"] call ALIVE_fnc_hashGet;

                    // ["ALIVE ATO %1 - %3 Nodes: %2", _logic, _nodes, count _nodes] call ALIVE_fnc_dump;
                    {
                        private _pos = [0,0,0];
                        private _dir = 0;
                        private _helipad = nil;
                        if (_x isKindOf "HeliH") then {
                            _pos = position _x;
                            _dir = direction _x;
                            _helipad = _x;
                        } else {
                            _helipad = nearestObject [position _x, "HeliH"];
                        };

                        if (!isNil "_helipad") then {

                            _pos = position _helipad;
                            _dir = getdir _helipad;

                            // Check helipad is not allocated to unarmed heli
                            private _nearbyObj = nearestObjects [position _helipad, ["Helicopter"], 10];
                            private _nearbyProfiles = [position _helipad, 10, [_side,"vehicle","Helicopter"]] call ALIVE_fnc_getNearProfiles;

                            if (count _nearbyObj == 0 && count _nearbyProfiles == 0) then {

                                private _vehicleClass = _heliClasses call BIS_fnc_selectRandom;

                                private _tmp = [_vehicleClass,_side,_faction,"CAPTAIN",_pos,_dir,false,_faction,false] call ALIVE_fnc_createProfilesCrewedVehicle;
                                {
                                    // _x call ALIVE_fnc_inspectHash;
                                    if ([_x,"type"] call ALiVE_fnc_hashGet == "entity") then {
                                        _profiles pushback ([_x,"profileID"] call ALiVE_fnc_hashGet);
                                    };
                                } foreach _tmp;
                            };
                        };
                    } forEach _nodes;
                };

                // IF there are no helipads available, we want atleast 1 chopper. Spawn a composition
                if (count _profiles == 0) then {
                    // Spawn a heliport
                    private _pos = [_baseCluster,"center"] call ALiVE_fnc_HashGet;
                    private _size = [_baseCluster,"size",150] call ALiVE_fnc_HashGet;
                    private _heliport = nil;
                    private _flatPos = [_pos,_size,30] call ALiVE_fnc_findFlatArea;

                    if (isNil QMOD(COMPOSITIONS_LOADED)) then {

                        // Get a composition
                        private _compType = "Military";
                        If (_faction call ALiVE_fnc_factionSide == RESISTANCE) then {
                            _compType = "Guerrilla";
                        };

                        _heliport = selectRandom ([_compType, ["Heliports"], [], _faction] call ALiVE_fnc_getCompositions);

                        if !(isNil "_heliport") then {
                            private _nearRoad = [_flatpos,750,true] call ALiVE_fnc_getClosestRoad;

                            private _direct = if (_nearRoad distance _flatpos > 5) then {
                                private _road = roadat _nearRoad;
                                private _roadConnectedTo = roadsConnectedTo _road;
                                if (count _roadConnectedTo > 0) then {
                                    private _connectedRoad = _roadConnectedTo select 0;
                                    (_road getDir _connectedRoad)
                                } else {
                                    90
                                };
                            } else {
                                0
                            };

                            // [_logic,"createMarker",[_nearRoad,_side,str(_direct),0]] call MAINCLASS;

                            [_heliport, _flatPos, _direct, _faction] call ALiVE_fnc_spawnComposition;

                            private _helipad = nearestObject [_flatpos, "HeliH"];

                            if !(isNull _helipad) then {

                                // remove any pre-placed aircraft on composition?
                                private _nearbyObj = nearestObjects [position _helipad, ["Helicopter"], 20];
                                if (count _nearbyObj > 0) then {
                                    {
                                        deleteVehicle _x;
                                    }foreach _nearbyObj;
                                };

                                private _vehicleClass = selectRandom _heliClasses;

                                private _tmp = [_vehicleClass,_side,_faction,"CAPTAIN",position _helipad,direction _helipad,true,_faction,false] call ALIVE_fnc_createProfilesCrewedVehicle;
                                {
                                    // _x call ALIVE_fnc_inspectHash;
                                    if ([_x,"type"] call ALiVE_fnc_hashGet == "entity") then {
                                        _profiles pushback ([_x,"profileID"] call ALiVE_fnc_hashGet);
                                    };
                                } foreach _tmp;
                            };
                        };
                    };
                };

                if(_debug) then {
                    ["ALIVE ATO %1 - %3 Helicopters to be added: %2", _logic, _profiles, count _profiles] call ALIVE_fnc_dump;
                };

                // Place planes
                private _airClasses = [0,_faction,"Plane"] call ALiVE_fnc_findVehicleType;

                // Remove unarmed classes
                {
                    if !([_x] call ALiVE_fnc_isArmed) then {
                        _airClasses set [_forEachIndex, -1];
                    };
                } foreach _airClasses;

                _airClasses = _airClasses - [-1];

                if(count _airClasses > 0) then {

                    private _nodes = [_baseCluster, "nodes"] call ALIVE_fnc_hashGet;

                    private _buildings = [_nodes, (ALIVE_airBuildingTypes + ALIVE_militaryAirBuildingTypes)] call ALIVE_fnc_findBuildingsInClusterNodes;
                    // ["ALIVE ATO %1 - %3 Hangar Buildings: %2", _logic, _buildings, count _buildings] call ALIVE_fnc_dump;

                    if (count _buildings == 0) then {
                        // No hangars, use HQ and check for runways
                        _buildings = [[_logic, "HQBuilding"] call MAINCLASS];
                    };

                    private _firstbuilding = true;

                    {
                        // Check hangar is not allocated to a plane
                        private _nearbyObj = nearestObjects [position _x, ["Plane","Helicopter"], 20];
                        private _nearbyProfiles = [position _x, 20, [_side,"vehicle","Plane"]] call ALIVE_fnc_getNearProfiles;
                        private _availablePlane = true;

                        if (count _nearbyObj == 0 && count _nearbyProfiles == 0) then {
                            if (_firstbuilding || random 1 > 0.30) then {

                                private _posi = [0,0,0];
                                private _dire = 0;
                                private _vehicleClass = _airClasses call BIS_fnc_selectRandom;

                                // Find safe place to put aircraft
                                private ["_pavement","_runway","_position"];
                                if (([typeOf _x, "hangar"] call CBA_fnc_find != -1 || [typeOf _x, "Hangar"] call CBA_fnc_find != -1) && _vehicleClass iskindof "Plane") then {
                                    _posi = position _x;
                                    _dire = direction _x;
                                } else {

                                    // find a taxiway
                                    _runway = [];
                                    {
                                        if ( (str(_x) find "taxiway" != -1 && typeof _x == "") || str(_x) find "invisible" != -1 ) then {
                                            _runway pushback _x;
                                        };
                                    } foreach (nearestObjects [position _x, [], 400]);

                                    if (count _runway > 0) then {
                                        // diag_log format["Cannot find hangar, choosing safe taxiway from: %1", _runway];
                                        _pavement = selectRandom _runway;
                                        _posi = [position _pavement, 0, 75, 20, 0, 0.2, 0] call BIS_fnc_findSafePos;
                                        _dire = direction _pavement;
                                    } else {

                                        // No safe place for plane, try to place VTOL instead
                                        diag_log format["Cannot find hangar or taxiway, looking for safe place to put aircraft %1", _vehicleClass];
                                        _availablePlane = false;

                                        If !(_vehicleClass isKindOf "VTOL_Base_F") then {
                                            // Find a vtol aircraft,
                                            {
                                                if (_vehicleClass isKindOf "VTOL_Base_F") then {
                                                    _vehiclesClass = _x;
                                                    _availablePlane = true;
                                                };
                                            } foreach _airClasses;
                                        };

                                        _posi = [position _x, 5, 200, 30, 0, 0.2, 0] call BIS_fnc_findSafePos;
                                        _dire = direction _x;
                                    };

                                    if (_availablePlane) then {
                                       // No Hangar, then place one somewhere (if available) and plane is available

                                        if (isNil QMOD(COMPOSITIONS_LOADED)) then {

                                            // Get a composition
                                            private _compType = "Military";
                                            If (_faction call ALiVE_fnc_factionSide == RESISTANCE) then {
                                                _compType = "Guerrilla";
                                            };

                                            private _hangar = selectRandom ([_compType, ["Airports"], ["Medium"], _faction] call ALiVE_fnc_getCompositions);

                                            private _flatPos = [position _x,150,50] call ALiVE_fnc_findFlatArea;

                                            [_hangar, _flatPos, direction _x, _faction] call ALiVE_fnc_spawnComposition;

                                        };
                                    };
                                };

                                if (_availablePlane) then {
                                    // Place a hangar

                                    // Place Aircraft
                                    private _tmp = [_vehicleClass,_side,_faction,_posi,_dire,false,_faction] call ALIVE_fnc_createProfileVehicle;
                                    // _tmp call ALIVE_fnc_inspectHash;
                                    _profiles pushback ([_tmp, "profileID"] call ALIVE_fnc_hashGet);
                                };

                            };
                            _firstbuilding = false;
                        };
                    } forEach _buildings;
                };

                if(_debug) then {
                    ["ALIVE ATO %1 - %3 total aircraft to be added: %2", _logic, _profiles, count _profiles] call ALIVE_fnc_dump;
                };

                // Add new profiles to module
                {
                    private _profileID = _x;
                    private _profile = [ALIVE_profileHandler, "getProfile",_profileID] call ALIVE_fnc_profileHandler;

                    if !(isnil "_profile") then {
                        [_logic,"registerProfile",[_profileID,_baseAirspace]] call MAINCLASS;
                    };
                } foreach _profiles;
            };

            // set as initial analysis complete
            _logic setVariable ["initialAnalysisComplete", true];

            // DEBUG -------------------------------------------------------------------------------------
            if(_debug) then {
                ["ALIVE ATO %1 - Analysis completed",_logic] call ALIVE_fnc_dump;
                ["----------------------------------------------------------------------------------------"] call ALIVE_fnc_dump;
                ["ALIVE ATO - Analysis %1", _logic] call ALIVE_fnc_dump;
                ["ALIVE ATO - OPCOMs: %1", count _modules] call ALIVE_fnc_dump;
                ["ALIVE ATO - Factions: %1", [_logic, "factions"] call MAINCLASS] call ALIVE_fnc_dump;
                ["ALIVE ATO - Air Assets: %1", count (([_logic,"assets"] call MAINCLASS) select 1)] call ALIVE_fnc_dump;
                ["ALIVE ATO - Assets by Airspace:"] call ALIVE_fnc_dump;
                ([_logic,"airspaceAssets"] call MAINCLASS) call ALIVE_fnc_inspectHash;
            };
            // DEBUG -------------------------------------------------------------------------------------

            // Broadcast radio message
            private _faction = [_logic, "faction"] call MAINCLASS;
            private _location = mapGridPosition (position ([_logic, "HQBuilding"] call MAINCLASS));
            private _side = [_logic, "side"] call MAINCLASS;
            private _sideObject = [_side] call ALIVE_fnc_sideTextToObject;
            private _factionName = getText((_faction call ALiVE_fnc_configGetFactionClass) >> "displayName");
            private _hqClass = switch (_sideObject) do {
                case WEST: {
                    "BLU"
                };
                case EAST: {
                    "OPF"
                };
                case RESISTANCE: {
                    "IND"
                };
                default {
                    "HQ"
                };
            };
            private _HQ = getText(configFile >> "CfgHQIdentities" >> _hqClass >> "name");

            private _message = format[localize "STR_ALIVE_ATO_ESTABLISHED", _HQ, _factionName, _location];

            // If no air assets, exit
            if (count (([_logic,"assets"] call MAINCLASS) select 1) == 0) exitWith {
                ["ALIVE ATO %1 - Warning, operations are being suspended as there are no available air assets within the airspace.", _logic] call ALIVE_fnc_dump;
                _message = format[localize "STR_ALIVE_ATO_NOT_ESTABLISHED", _HQ, _factionName];
                private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;
            };

            // send a message to all side players from HQ
            private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
            [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

            // register the module
            [ALIVE_ATOGlobalRegistry,"register",_logic] call ALIVE_fnc_ATOGlobalRegistry;

            // start listening for ATO events
            [_logic,"listen"] call MAINCLASS;

            // trigger main processing loop
            [_logic, "monitor"] call MAINCLASS;
        };
    };

    case "listen": {
        private["_listenerID"];

        _listenerID = [ALIVE_eventLog, "addListener",[_logic, ["ATO_REQUEST","ATO_STATUS_REQUEST","ATO_CANCEL_REQUEST"]]] call ALIVE_fnc_eventLog;
        _logic setVariable ["listenerID", _listenerID];
    };

    case "handleEvent": {
        private["_event","_type","_eventData"];

        if(typeName _args == "ARRAY") then {

            _event = _args;
            _type = [_event, "type"] call ALIVE_fnc_hashGet;

            [_logic, _type, _event] call MAINCLASS;

        };
    };

    case "ATO_STATUS_REQUEST": { //TODO

        private["_debug","_event","_eventData","_eventQueue","_side","_factions","_eventFaction","_eventSide","_factionFound",
        "_moduleFactions","_eventPlayerID","_eventRequestID"];

        if(typeName _args == "ARRAY") then {

            _event = _args;
            _eventData = [_event, "data"] call ALIVE_fnc_hashGet;

            _side = [_logic, "side"] call MAINCLASS;
            _factions = [_logic, "factions"] call MAINCLASS;

            _eventFaction = _eventData select 0;
            _eventSide = _eventData select 1;
            _eventRequestID = _eventData select 2;
            _eventPlayerID = _eventData select 3;

            // check if the faction in the event is handled
            // by this module
            _factionFound = false;

            {
                _moduleFactions = _x select 1;
                if(_eventFaction in _moduleFactions) then {
                    _factionFound = true;
                };
            } forEach _factions;

            // faction not handled by this mil air tasking orders module
            if!(_factionFound) then {

                private ["_sideOPCOMModules","_factionOPCOMModules","_checkModule","_moduleType","_handler","_OPCOMSide","_OPCOMFactions","_OPCOMHasLogistics","_mod"];

                _sideOPCOMModules = [];
                _factionOPCOMModules = [];

                // loop through OPCOM modules with mil air tasking orders synced and find any matching the events side and faction
                {

                    _checkModule = _x;
                    _moduleType = _x getVariable "moduleType";

                    if!(isNil "_moduleType") then {

                        if(_moduleType == "ALIVE_OPCOM") then {

                            _handler = _checkModule getVariable "handler";
                            _OPCOMSide = [_handler,"side"] call ALIVE_fnc_hashGet;
                            _OPCOMFactions = [_handler,"factions"] call ALIVE_fnc_hashGet;
                            _OPCOMHasLogistics = false;

                            for "_i" from 0 to ((count synchronizedObjects _checkModule)-1) do {

                                _mod = (synchronizedObjects _checkModule) select _i;

                                if ((typeof _mod) == "ALiVE_mil_ato") then {
                                    _OPCOMHasLogistics = true;
                                };
                            };

                            if(_OPCOMHasLogistics) then {

                                if(_OPCOMSide == _eventSide) then {
                                    _sideOPCOMModules pushback _checkModule;
                                };

                                {
                                    if(_x == _eventFaction) then {
                                        _factionOPCOMModules pushback _checkModule;
                                    };

                                } forEach _OPCOMFactions;

                            };
                        };
                    };
                } forEach (entities "Module_F");

                // if no mil air tasking orders handles this faction, and there is more than one mil
                // air tasking orders for this side return an error
                if(((count _factionOPCOMModules == 0) && (count _sideOPCOMModules > 1)) || ((count _factionOPCOMModules == 0) && (count _sideOPCOMModules == 0))) then {
                    _factionFound = false;
                };

                // if no mil air tasking orders handles this faction, and there is one mil
                // air tasking orders for this side and this module handles that side
                if((count _factionOPCOMModules == 0) && (count _sideOPCOMModules == 1) && (_side == _eventSide)) then {
                    _factionFound = true;
                };

            };

            if!(_factionFound) exitWith {};

            if(_factionFound) then {

                private ["_eventQueue","_response","_responseItem","_playerRequested","_eventData","_logEvent","_playerID",
                "_eventState","_eventType","_eventATO","_requestID","_transportProfiles","_position","_playerRequestProfileID","_profile"];

                // get the event data for this player

                _eventQueue = [_logic, "eventQueue"] call MAINCLASS;

                _response = [];

                if((count (_eventQueue select 2)) > 0) then {

                    {
                        _playerRequested = [_x, "playerRequested"] call ALIVE_fnc_hashGet;

                        if(_playerRequested) then {
                            _eventData = [_x, "data"] call ALIVE_fnc_hashGet;
                            _playerID = _eventData select 5;
                            _eventType = _eventData select 4;
                            _eventATO = _eventData select 3;

                            if(_eventPlayerID == _playerID) then {

                                _responseItem = [];

                                _requestID = _eventATO select 0;
                                _eventState = [_x, "state"] call ALIVE_fnc_hashGet;
                                _transportProfiles = [_x, "transportProfiles"] call ALIVE_fnc_hashGet;

                                _positions = [];

                                if(count _transportProfiles > 0) then {

                                    {
                                        _profile = [ALIVE_profileHandler, "getProfile", _x] call ALIVE_fnc_profileHandler;

                                        if!(isNil "_profile") then {
                                            _position = _profile select 2 select 2;
                                            _positions pushBack _position;
                                        };

                                    } forEach _transportProfiles;

                                };

                                _responseItem pushBack _eventType;
                                _responseItem pushBack _requestID;
                                _responseItem pushBack _eventState;
                                _responseItem pushBack _positions;

                                _response pushBack _responseItem;
                            };
                        };

                    } forEach (_eventQueue select 2);

                };

                // respond to player request
                _logEvent = ['ATO_RESPONSE', [_eventRequestID,_eventPlayerID,_response],"Joint Forces Air Component Commander","STATUS"] call ALIVE_fnc_event;
                [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;

            };
        };
    };

    case "ATO_CANCEL_REQUEST": { //TODO

        private["_debug","_event","_eventData","_eventQueue","_side","_factions","_eventFaction","_eventSide","_factionFound",
        "_moduleFactions","_eventPlayerID","_eventRequestID","_eventCancelRequestID"];

        if(typeName _args == "ARRAY") then {

            _event = _args;
            _eventData = [_event, "data"] call ALIVE_fnc_hashGet;

            _side = [_logic, "side"] call MAINCLASS;
            _factions = [_logic, "factions"] call MAINCLASS;

            _eventFaction = _eventData select 0;
            _eventSide = _eventData select 1;
            _eventRequestID = _eventData select 2;
            _eventPlayerID = _eventData select 3;
            _eventCancelRequestID = _eventData select 4;

            // check if the faction in the event is handled
            // by this module
            _factionFound = false;

            {
                _moduleFactions = _x select 1;
                if(_eventFaction in _moduleFactions) then {
                    _factionFound = true;
                };
            } forEach _factions;

            // faction not handled by this mil air tasking orders module
            if!(_factionFound) then {

                private ["_sideOPCOMModules","_factionOPCOMModules","_checkModule","_moduleType","_handler","_OPCOMSide","_OPCOMFactions","_OPCOMHasLogistics","_mod"];

                _sideOPCOMModules = [];
                _factionOPCOMModules = [];

                // loop through OPCOM modules with mil air tasking orders synced and find any matching the events side and faction
                {

                    _checkModule = _x;
                    _moduleType = _x getVariable "moduleType";

                    if!(isNil "_moduleType") then {

                        if(_moduleType == "ALIVE_OPCOM") then {

                            _handler = _checkModule getVariable "handler";
                            _OPCOMSide = [_handler,"side"] call ALIVE_fnc_hashGet;
                            _OPCOMFactions = [_handler,"factions"] call ALIVE_fnc_hashGet;
                            _OPCOMHasLogistics = false;

                            for "_i" from 0 to ((count synchronizedObjects _checkModule)-1) do {

                                _mod = (synchronizedObjects _checkModule) select _i;

                                if ((typeof _mod) == "ALiVE_mil_ato") then {
                                    _OPCOMHasLogistics = true;
                                };
                            };

                            if(_OPCOMHasLogistics) then {

                                if(_OPCOMSide == _eventSide) then {
                                    _sideOPCOMModules pushback _checkModule;
                                };

                                {
                                    if(_x == _eventFaction) then {
                                        _factionOPCOMModules pushback _checkModule;
                                    };

                                } forEach _OPCOMFactions;

                            };
                        };
                    };
                } forEach (entities "Module_F");

                // if no mil air tasking orders handles this faction, and there is more than one mil
                // air tasking orders for this side return an error
                if(((count _factionOPCOMModules == 0) && (count _sideOPCOMModules > 1)) || ((count _factionOPCOMModules == 0) && (count _sideOPCOMModules == 0))) then {
                    _factionFound = false;
                };

                // if no mil air tasking orders handles this faction, and there is one mil
                // air tasking orders for this side and this module handles that side
                if((count _factionOPCOMModules == 0) && (count _sideOPCOMModules == 1) && (_side == _eventSide)) then {
                    _factionFound = true;
                };

            };

            if!(_factionFound) exitWith {};

            if(_factionFound) then {

                private ["_eventQueue","_response","_responseItem","_playerRequested","_eventID","_eventData","_logEvent","_playerID",
                "_eventState","_eventType","_eventATO","_responseItem","_eventCargoProfiles","_infantryProfiles","_armourProfiles",
                "_mechanisedProfiles","_motorisedProfiles","_planeProfiles","_heliProfiles","_eventAssets","_allRequestedProfiles","_anyActive",
                "_transportProfiles","_transportVehiclesProfiles","_requestID","_position","_playerRequestProfileID","_profile","_active","_profileType"];

                // get the event data for this player

                _eventQueue = [_logic, "eventQueue"] call MAINCLASS;

                _response = [];

                if((count (_eventQueue select 2)) > 0) then {

                    {
                        _playerRequested = [_x, "playerRequested"] call ALIVE_fnc_hashGet;

                        if(_playerRequested) then {
                            _eventID = [_x, "id"] call ALIVE_fnc_hashGet;
                            _eventData = [_x, "data"] call ALIVE_fnc_hashGet;
                            _playerID = _eventData select 5;
                            _eventType = _eventData select 4;
                            _eventATO = _eventData select 3;

                            if(_eventPlayerID == _playerID) then {

                                _responseItem = [];

                                _requestID = _eventATO select 0;

                                if(_requestID == _eventCancelRequestID) then {

                                    //_x call ALIVE_fnc_inspectHash;

                                    _eventCargoProfiles = [_x, "cargoProfiles"] call ALIVE_fnc_hashGet;

                                    _transportProfiles = [_x, "transportProfiles"] call ALIVE_fnc_hashGet;
                                    _transportVehiclesProfiles = [_x, "transportVehiclesProfiles"] call ALIVE_fnc_hashGet;

                                    _infantryProfiles = [_eventCargoProfiles, 'infantry'] call ALIVE_fnc_hashGet;
                                    _armourProfiles = [_eventCargoProfiles, 'armour'] call ALIVE_fnc_hashGet;
                                    _mechanisedProfiles = [_eventCargoProfiles, 'mechanised'] call ALIVE_fnc_hashGet;
                                    _motorisedProfiles = [_eventCargoProfiles, 'motorised'] call ALIVE_fnc_hashGet;
                                    _planeProfiles = [_eventCargoProfiles, 'plane'] call ALIVE_fnc_hashGet;
                                    _heliProfiles = [_eventCargoProfiles, 'heli'] call ALIVE_fnc_hashGet;

                                    _allRequestedProfiles = [];
                                    _anyActive = false;

                                    {
                                        _profile = [ALIVE_profileHandler, "getProfile", _x] call ALIVE_fnc_profileHandler;
                                        if!(isNil "_profile") then {
                                            _active = _profile select 2 select 1;
                                            if(_active) then {
                                                _anyActive = true;
                                            };
                                            _allRequestedProfiles pushBack _profile;
                                        };

                                    } forEach _transportProfiles;

                                    {
                                        _profile = [ALIVE_profileHandler, "getProfile", _x] call ALIVE_fnc_profileHandler;
                                        if!(isNil "_profile") then {
                                            _active = _profile select 2 select 1;
                                            if(_active) then {
                                                _anyActive = true;
                                            };
                                            _allRequestedProfiles pushBack _profile;
                                        };

                                    } forEach _transportVehiclesProfiles;

                                    {
                                        _profile = [ALIVE_profileHandler, "getProfile", _x select 0] call ALIVE_fnc_profileHandler;
                                        if!(isNil "_profile") then {
                                            _active = _profile select 2 select 1;
                                            if(_active) then {
                                                _anyActive = true;
                                            };
                                            _allRequestedProfiles pushBack _profile;
                                        };

                                    } forEach _infantryProfiles;

                                    {
                                        {
                                            _profile = [ALIVE_profileHandler, "getProfile", _x] call ALIVE_fnc_profileHandler;
                                            if!(isNil "_profile") then {
                                                _active = _profile select 2 select 1;
                                                if(_active) then {
                                                    _anyActive = true;
                                                };
                                                _allRequestedProfiles pushBack _profile;
                                            };
                                        } forEach _x;

                                    } forEach _armourProfiles;

                                    {
                                        {
                                            _profile = [ALIVE_profileHandler, "getProfile", _x] call ALIVE_fnc_profileHandler;
                                            if!(isNil "_profile") then {
                                                _active = _profile select 2 select 1;
                                                if(_active) then {
                                                    _anyActive = true;
                                                };
                                                _allRequestedProfiles pushBack _profile;
                                            };
                                        } forEach _x;

                                    } forEach _mechanisedProfiles;

                                    {
                                        {
                                            _profile = [ALIVE_profileHandler, "getProfile", _x] call ALIVE_fnc_profileHandler;
                                            if!(isNil "_profile") then {
                                                _active = _profile select 2 select 1;
                                                if(_active) then {
                                                    _anyActive = true;
                                                };
                                                _allRequestedProfiles pushBack _profile;
                                            };
                                        } forEach _x;

                                    } forEach _motorisedProfiles;

                                    {
                                        {
                                            _profile = [ALIVE_profileHandler, "getProfile", _x] call ALIVE_fnc_profileHandler;
                                            if!(isNil "_profile") then {
                                                _active = _profile select 2 select 1;
                                                if(_active) then {
                                                    _anyActive = true;
                                                };
                                                _allRequestedProfiles pushBack _profile;
                                            };
                                        } forEach _x;

                                    } forEach _planeProfiles;

                                    {
                                        {
                                            _profile = [ALIVE_profileHandler, "getProfile", _x] call ALIVE_fnc_profileHandler;
                                            if!(isNil "_profile") then {
                                                _active = _profile select 2 select 1;
                                                if(_active) then {
                                                    _anyActive = true;
                                                };
                                                _allRequestedProfiles pushBack _profile;
                                            };
                                        } forEach _x;

                                    } forEach _heliProfiles;

                                    if(_anyActive) then {

                                        // respond to player request
                                        _logEvent = ['LOGCOM_RESPONSE', [_eventRequestID,_eventPlayerID,_response],"air tasking orders","CANCEL_FAILED"] call ALIVE_fnc_event;
                                        [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;

                                    }else{

                                        // delete all profiles

                                        {
                                            _profileType = _x select 2 select 5;
                                            if(_profileType == 'entity') then {
                                                [_x, "destroy"] call ALIVE_fnc_profileEntity;
                                            }else{
                                                [_x, "destroy"] call ALIVE_fnc_profileVehicle;
                                            };

                                        } forEach _allRequestedProfiles;

                                        _eventAssets = [_x, "eventAssets"] call ALIVE_fnc_hashGet;

                                        {
                                            deleteVehicle _x;
                                        } forEach _eventAssets;

                                        // set state to event complete
                                        [_x, "state", "eventComplete"] call ALIVE_fnc_hashSet;
                                        [_eventQueue, _eventID, _x] call ALIVE_fnc_hashSet;

                                        // respond to player request
                                        _logEvent = ['LOGCOM_RESPONSE', [_eventRequestID,_eventPlayerID,_response],"air tasking orders","CANCEL_OK"] call ALIVE_fnc_event;
                                        [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;

                                    };
                                };
                            };
                        };

                    } forEach (_eventQueue select 2);

                };
            };
        };
    };

    case "ATO_REQUEST": {

        if(typeName _args == "ARRAY") then {

            // EVENT DATA STRUCTURE is hash
            // type : 'ATO_REQUEST'
            // data : [_type,_side,_faction,_airspace,[_ROE,_altitude,_speed,minWeaponState,minFuelState,_range,_duration,_targets],_requestID,_playerID]
            // from: "OPCOM"
            // message : "DENIED"
            // id : 0
            // Requestors can be OPCOM, ATO, PLAYER

            private _debug = [_logic, "debug"] call MAINCLASS;
            private _types = [_logic, "types"] call MAINCLASS;
            private _event = _args;
            private _eventData = [_event, "data"] call ALIVE_fnc_hashGet;
            private _eventType = _eventData select 0;

            private _initComplete = true;

            // TODO
            if (_eventType == "PR_STRIKE" || _eventType == "PR_RECCE" || _eventType == "PR_CAS") then {
                _initComplete = _logic getVariable "initialAnalysisComplete";
                if!(_initComplete) then {
                    _requestID = _eventData select 5;
                    _playerID = _eventData select 6;
                    // respond to player request
                    _logEvent = ['ATO_RESPONSE', [_requestID,_playerID],"Joint Forces Air Component Commander","DENIED_WAITING_INIT"] call ALIVE_fnc_event;
                    [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;
                };
            };

            if !(_initComplete) exitWith {};

            private _side = [_logic, "side"] call MAINCLASS;
            private _factions = [_logic, "factions"] call MAINCLASS;
            private _eventSide = _eventData select 1;
            private _eventFaction = _eventData select 2;
            private _airspace = _eventData select 3;

            // check if the faction in the event is handled
            // by this module
            private _factionFound = false;
            if(_eventFaction in _factions) then {
                _factionFound = true;
            };

            // check if any other mil air tasking orders modules can handle this event
            if(_eventType == "PR_STRIKE" || _eventType == "PR_RECCE" || _eventType == "PR_CAS") then {

                // faction not handled by this mil air tasking orders module
                if!(_factionFound) then {

                    private _sideOPCOMModules = [];
                    private _factionOPCOMModules = [];

                    // loop through OPCOM modules with mil air tasking orders synced and find any matching the events side and faction
                    {
                        private _checkModule = _x;
                        private _moduleType = _x getVariable "moduleType";

                        if!(isNil "_moduleType") then {

                            if(_moduleType == "ALIVE_OPCOM") then {

                                private _handler = _checkModule getVariable "handler";
                                private _OPCOMSide = [_handler,"side"] call ALIVE_fnc_hashGet;
                                private _OPCOMFactions = [_handler,"factions"] call ALIVE_fnc_hashGet;
                                private _OPCOMHasATO = false;

                                for "_i" from 0 to ((count synchronizedObjects _checkModule)-1) do {

                                    private _mod = (synchronizedObjects _checkModule) select _i;

                                    if ((typeof _mod) == "ALiVE_mil_ato") then {
                                        _OPCOMHasATO = true;
                                    };
                                };

                                if(_OPCOMHasATO) then {

                                    if(_OPCOMSide == _eventSide) then {
                                        _sideOPCOMModules pushback _checkModule;
                                    };

                                    {
                                        if(_x == _eventFaction) then {
                                            _factionOPCOMModules pushback _checkModule;
                                        };

                                    } forEach _OPCOMFactions;

                                };
                            };
                        };
                    } forEach (entities "Module_F");

                    // if no mil air tasking orders handles this faction, and there is more than one mil air tasking orders for this side return an error
                    if(((count _factionOPCOMModules == 0) && (count _sideOPCOMModules > 1)) || ((count _factionOPCOMModules == 0) && (count _sideOPCOMModules == 0))) then {
                        private _playerID = _eventData select 6;
                        private _requestID = _eventData select 5;
                        // respond to player request
                        _logEvent = ['ATO_RESPONSE', [_requestID,_playerID],"Joint Forces Air Component Commander","DENIED_FACTION_HANDLER_NOT_FOUND"] call ALIVE_fnc_event;
                        [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;
                    };

                    // if no mil air tasking orders handles this faction, and there is one mil air tasking orders for this side and this module handles that side
                    if((count _factionOPCOMModules == 0) && (count _sideOPCOMModules == 1) && (_side == _eventSide)) then {

                        _factionFound = true;

                        _eventData set [1,_factions select 0];
                        [_event, "data", _eventData] call ALIVE_fnc_hashSet;
                        _eventFaction = _factions select 0;
                    };
                };
            };

            if!(_factionFound) exitWith {};

            if(_factionFound) then {


                 // For radio broadcasts
                private _sideObject = [_side] call ALIVE_fnc_sideTextToObject;
                private _factionName = getText((_eventFaction call ALiVE_fnc_configGetFactionClass) >> "displayName");
                private _hqClass = switch (_sideObject) do {
                    case WEST: {
                        "BLU"
                    };
                    case EAST: {
                        "OPF"
                    };
                    case RESISTANCE: {
                        "IND"
                    };
                    default {
                        "HQ"
                    };
                };
                private _HQID = getText(configFile >> "CfgHQIdentities" >> _hqClass >> "name");


                // Check if this module is operating and has assets

                // Check HQ is alive or baseCluster is not captured
                private _baseCluster = [_logic, "currentBase"] call MAINCLASS;
                private _baseCaptured = false;
                private _HQIsALive = true;

                private _dominantFaction = [[_baseCluster,"center"] call ALiVE_fnc_hashGet] call ALiVE_fnc_getDominantFaction;
                if (isNil "_dominantFaction") then {_dominantFaction = _eventFaction;};
                if !([(_dominantFaction call ALiVE_fnc_factionSide), [_eventSide] call ALIVE_fnc_sideTextToObject] call BIS_fnc_sideIsFriendly) then {
                    _baseCaptured = true;
                };

                private _HQ = [_logic,"HQBuilding",nil] call MAINCLASS;
                if (!isNil "_HQ") then {
                    _HQIsALive = alive _HQ;
                };

                if (_debug) then {
                     ["ALIVE ATO %4 - ATO HQ online: %1 Base Captured: %2 Dominant Faction: %3", _HQIsAlive,_baseCaptured,_dominantFaction, _logic] call ALIVE_fnc_dump;
                };

                if (_HQIsAlive && !_baseCaptured) then {

                    // Check all available assets
                    private _assets = [ALIVE_globalATO, _eventFaction] call ALIVE_fnc_hashGet;

                    // DEBUG -------------------------------------------------------------------------------------
                    if(_debug) then {
                        ["ALIVE ATO - Global ATO:"] call ALIVE_fnc_dump;
                        ALIVE_globalATO call ALIVE_fnc_inspectHash;
                    };
                    // DEBUG -------------------------------------------------------------------------------------

                    // if there are still assets available
                    if(count (_assets select 1) > 0) then {

                        private _available = false;

                        if(_eventType in _types) then {

                            _available = true;

                            // set the state of the event
                            [_event, "state", "requested"] call ALIVE_fnc_hashSet;

                            // set the player requested flag on the event
                            [_event, "playerRequested", false] call ALIVE_fnc_hashSet;

                        };

                        if(_eventType == "PR_STRIKE" || _eventType == "PR_RECCE" || _eventType == "PR_CAS") then {

                            private _requestID = _eventData select 5;
                            private _playerID = _eventData select 6;

                            // if it's a player request
                            // accept automatically

                            _available = true;

                            // set the state of the event
                            [_event, "state", "playerRequested"] call ALIVE_fnc_hashSet;

                            // set the player requested flag on the event
                            [_event, "playerRequested", true] call ALIVE_fnc_hashSet;

                            // respond to player request
                            private _logEvent = ['ATO_RESPONSE', [_requestID,_playerID],"Joint Forces Air Component Commander","ACKNOWLEDGED"] call ALIVE_fnc_event;
                            [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;

                        };

                        if (_debug) then {
                            _event call ALIVE_fnc_inspectHash;
                        };

                        if(_available) then {

                            // Set event ID
                            private _eventID = [_event, "id"] call ALIVE_fnc_hashGet;

                            // set the time the event was received
                            [_event, "time", time] call ALIVE_fnc_hashSet;

                            // set the state data array of the event
                            [_event, "stateData", []] call ALIVE_fnc_hashSet;

                            // set the profiles array of the event
                            [_event, "friendlyProfiles", []] call ALIVE_fnc_hashSet;
                            [_event, "enemyProfiles", []] call ALIVE_fnc_hashSet;
                            [_event, "playerRequestProfiles", []] call ALIVE_fnc_hashSet;

                            // store the event on the event queue
                            private _eventQueue = [_logic, "eventQueue"] call MAINCLASS;
                            [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;

                            // DEBUG -------------------------------------------------------------------------------------
                            if(_debug) then {
                                ["ALIVE ATO %1 - ATO request event received", _logic] call ALIVE_fnc_dump;
                                ["ALIVE ATO - %2 available assets for %1", _side, count (_assets select 1)] call ALIVE_fnc_dump;
                                _event call ALIVE_fnc_inspectHash;
                            };
                            // DEBUG -------------------------------------------------------------------------------------

                            private _airspacePos = [];
                            if (typeName _airspace == "STRING") then {
                                _airspacePos = getMarkerPos _airspace;
                            } else {
                                _airspacePos = +_airspace;
                            };

                            //Radio Broadcast
                            private _message = format[localize "STR_ALIVE_ATO_REQUEST_ACKNOWLEDGED", _HQID, _factionName, _eventType, mapGridPosition _airspacePos];
                            // send a message to all side players from HQ
                            private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                            [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

                            // trigger analysis
                            [_logic,"onDemandAnalysis"] call MAINCLASS;


                        }else{

                            // nothing left after non allowed types ruled out

                        };
                    }else{

                        // DEBUG -------------------------------------------------------------------------------------
                        if(_debug) then {
                            ["ALIVE ATO %2 - Air Tasking request denied, Joint Forces Air Component Commander for %1 has no available air assets", _eventFaction, _logic] call ALIVE_fnc_dump;
                        };
                        // DEBUG -------------------------------------------------------------------------------------

                        //Radio Broadcast
                        private _message = format[localize "STR_ALIVE_ATO_UNAVAILABLE", _HQID];
                        // send a message to all side players from HQ
                        private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                        [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

                        if(_eventType == "PR_STRIKE" || _eventType == "PR_RECCE" || _eventType == "PR_CAS") then {

                            private _requestID = _eventData select 5;
                            private _playerID = _eventData select 6;

                            // respond to player request
                            private _logEvent = ['ATO_RESPONSE', [_requestID,_playerID],"Joint Forces Air Component Commander","DENIED_ATO_UNAVAILABLE"] call ALIVE_fnc_event;
                            [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;

                        };
                    };
                } else {
                    // DEBUG -------------------------------------------------------------------------------------
                    if(_debug) then {
                        ["ALIVE ATO %2 - Air Tasking request denied, Joint Forces Air Component Commander for %1 is not available", _eventFaction, _logic] call ALIVE_fnc_dump;
                    };
                    // DEBUG -------------------------------------------------------------------------------------

                    //Radio Broadcast
                    private _message = format[localize "STR_ALIVE_ATO_OVERRUN", _HQID, _factionName, mapGridPosition _HQ];
                    // send a message to all side players from HQ
                    private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                    [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

                    if(_eventType == "PR_STRIKE" || _eventType == "PR_RECCE" || _eventType == "PR_CAS") then {

                        private _requestID = _eventData select 5;
                        private _playerID = _eventData select 6;

                        // respond to player request
                        private _logEvent = ['ATO_RESPONSE', [_requestID,_playerID],"Joint Forces Air Component Commander","DENIED_ATO_UNAVAILABLE"] call ALIVE_fnc_event;
                        [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;

                    };
                };
            };

        };
    };

    // ATO prioritisation
    case "onDemandAnalysis": { // TODO

        if (isServer) then {

            // Check to see the current state of air assets

            private _debug = [_logic, "debug"] call MAINCLASS;
            private _analysisInProgress = _logic getVariable ["analysisInProgress", false];

            // if analysis not already underway
            if!(_analysisInProgress) then {

                _logic setVariable ["analysisInProgress", true];

                private _available = true;
                private _registryID = [_logic, "registryID"] call MAINCLASS;
                private _airspaceAssets = [_logic, "airspaceAssets"] call MAINCLASS;
                private _assets = [ALIVE_globalATO,_eventFaction] call ALIVE_fnc_hashGet;
                if(typeName _assets == "STRING") then {
                    _assets = call compile _assets;
                };

                // DEBUG -------------------------------------------------------------------------------------
                if(_debug) then {
                    ["ALIVE ATO %1 - Air component analysis started", _logic] call ALIVE_fnc_dump;
                };
                // DEBUG -------------------------------------------------------------------------------------

                // Check to see if we need to move base

                // If so relocate

                // Check to see if all existing assets are still available
                if (count (_assets select 1) == 0) then {
                    _available = false;
                };

                // if not order new assets from LOGCOM

                // Check to see if there are new assets?

                // Update assets and airspaceAssets

                // [ALIVE_ATOGlobalRegistry,"updateGlobalATO",[_registryID,_assets]] call ALIVE_fnc_ATOGlobalRegistry;

                // store the analysis results
                _requestAnalysis = [] call ALIVE_fnc_hashCreate;
                [_requestAnalysis, "available", _available] call ALIVE_fnc_hashSet;

                [_logic, "requestAnalysis", _requestAnalysis] call MAINCLASS;

                // DEBUG -------------------------------------------------------------------------------------
                if(_debug) then {
                    ["ALIVE ATO %1 - On demand analysis complete", _logic] call ALIVE_fnc_dump;
                    ["ALIVE ATO %2 - Air assets still available: %1",_available, _logic] call ALIVE_fnc_dump;
                };
                // DEBUG -------------------------------------------------------------------------------------

                _logic setVariable ["analysisInProgress", false];
            };
        };
    };

    // Airspace Management
    case "monitor": {
        if (isServer) then {

            // spawn monitoring loop - 1. to check for requests from OPCOM and 2. to scan airspace

            [_logic] spawn {

                private _logic = _this select 0;
                private _debug = [_logic, "debug"] call MAINCLASS;

                // DEBUG -------------------------------------------------------------------------------------
                if(_debug) then {
                    ["ALIVE ATO %1 - Request loop started", _logic] call ALIVE_fnc_dump;
                };
                // DEBUG -------------------------------------------------------------------------------------

                waituntil {

                    sleep (10);

                    if!([_logic, "pause"] call MAINCLASS) then {

                        private ["_requestAnalysis","_analysisInProgress","_eventQueue"];

                        _requestAnalysis = [_logic, "requestAnalysis"] call MAINCLASS;

                        // analysis has run
                        if(count _requestAnalysis > 0) then {

                            _analysisInProgress = _logic getVariable ["analysisInProgress", false];

                            // if analysis not processing
                            if!(_analysisInProgress) then {

                                // loop the event queue
                                // and manage each event
                                _eventQueue = [_logic, "eventQueue"] call MAINCLASS;

                                if((count (_eventQueue select 2)) > 0) then {

                                    {
                                        [_logic,"monitorEvent",[_x, _requestAnalysis]] call MAINCLASS;
                                    } forEach (_eventQueue select 2);

                                };

                            };

                        };

                    };

                    false
                };
            };

            [_logic] spawn {

                private _logic = _this select 0;
                private _debug = [_logic, "debug"] call MAINCLASS;
                private _side = [_logic,"side"] call MAINCLASS;
                private _faction = [_logic,"faction"] call MAINCLASS;

                // DEBUG -------------------------------------------------------------------------------------
                if(_debug) then {
                    ["ALIVE ATO %1 - Airspace Management loop started", _logic] call ALIVE_fnc_dump;
                };
                // DEBUG -------------------------------------------------------------------------------------

                waituntil {

                    sleep (60);

                    if!([_logic, "pause"] call MAINCLASS) then {

                        // Check to see if there is a CAP
                        private _airspace = [_logic,"airspace"] call MAINCLASS;
                        {

                            if ("CAP" in ([_logic,"types"] call MAINCLASS)) then {
                                private _currentOps = [_logic, "airspaceOps", _x] call MAINCLASS;
                                private _CAP = false;
                                {
                                    if ((_x select 0) == "CAP") exitWith {
                                        _CAP = true;
                                    };
                                } foreach _currentOps;

                                // If no cap then request one
                                if !(_CAP) then {
                                    private _type = "CAP";
                                    private _range = if ((getMarkerSize _x) select 0 < (getMarkerSize _x) select 1) then {(getMarkerSize _x) select 0} else {(getMarkerSize _x) select 1};
                                    private _args = [
                                        "WHITE",                // ROE
                                        DEFAULT_OP_HEIGHT,
                                        DEFAULT_SPEED,
                                        DEFAULT_MIN_WEAP_STATE,
                                        DEFAULT_MIN_FUEL_STATE,
                                        _range * 0.9,       // RADIUS
                                        DEFAULT_OP_DURATION,
                                        []                      // TARGETS
                                    ];
                                    private _event = ['ATO_REQUEST', [_type, _side, _faction, _x, _args],"ATO"] call ALIVE_fnc_event;
                                    private _eventID = [ALIVE_eventLog, "addEvent",_event] call ALIVE_fnc_eventLog;
                                };
                            };
                        } foreach _airspace;

                        // Check to see if there is an intruder in any airspace
                        if ("DCA" in ([_logic,"types"] call MAINCLASS)) then {

                            // Check for intruders in each managed airspace
                            private _intruders = [_logic, "scanAirspace"] call MAINCLASS;

                            // Grab the airspaces with intruders
                            private _airspaceIntruders = _intruders select 1;

                            {
                                // If intruder, check to see if there is an active DCA against it, if not scramble
                                private _bogeys = [_intruders, _x] call ALiVE_fnc_hashGet;
                                if (count _bogeys > 0) then {
                                    private _currentOps = [_logic, "airspaceOps", _x] call MAINCLASS;
                                    private _DCA = false;

                                    {
                                        if ((_x select 0) == "DCA") exitWith {
                                            // check all intruders are being intercepted?
                                            _DCA = true;
                                        };
                                    } foreach _currentOps;

                                    if !(_DCA) then {
                                        private _type = "DCA";
                                        private _range = if ((getMarkerSize _x) select 0 > (getMarkerSize _x) select 1) then {(getMarkerSize _x) select 0} else {(getMarkerSize _x) select 1};
                                        private _args = [
                                            "RED",                // ROE
                                            DEFAULT_OP_HEIGHT,
                                            "FULL",                 // SPEED MODE
                                            DEFAULT_MIN_WEAP_STATE,
                                            DEFAULT_MIN_FUEL_STATE,
                                            _range * 0.9,       // RADIUS / RANGE
                                            DEFAULT_OP_DURATION,
                                            _bogeys                 // TARGETS
                                        ];
                                        private _event = ['ATO_REQUEST', [_type, _side, _faction, _x, _args],"ATO"] call ALIVE_fnc_event;
                                        private _eventID = [ALIVE_eventLog, "addEvent",_event] call ALIVE_fnc_eventLog;
                                    };
                                };
                            } foreach _airspaceIntruders
                        };
                    };

                    false
                };
            };
        };
    };

    // Air Tasking Order Mission Framework
    case "monitorEvent": {

        private _debug = [_logic, "debug"] call MAINCLASS;
        private _registryID = [_logic, "registryID"] call MAINCLASS;
        private _event = _args select 0;
        private _requestAnalysis = _args select 1;

        private _side = [_logic, "side"] call MAINCLASS;
        private _eventQueue = [_logic, "eventQueue"] call MAINCLASS;
        private _isCarrier = [_logic, "isCarrier"] call MAINCLASS;

        private _eventID = [_event, "id"] call ALIVE_fnc_hashGet;
        private _eventData = [_event, "data"] call ALIVE_fnc_hashGet;
        private _eventTime = [_event, "time"] call ALIVE_fnc_hashGet;
        private _eventState = [_event, "state"] call ALIVE_fnc_hashGet;
        private _eventStateData = [_event, "stateData"] call ALIVE_fnc_hashGet;
        private _eventFriendlyProfiles = [_event, "friendlyProfiles"] call ALIVE_fnc_hashGet;
        private _eventEnemyProfiles = [_event, "enemyProfiles"] call ALIVE_fnc_hashGet;
        private _playerRequested = [_event, "playerRequested"] call ALIVE_fnc_hashGet;
        private _playerRequestProfiles = [_event, "playerRequestProfiles"] call ALIVE_fnc_hashGet;

        private _eventType = _eventData select 0;
        private _eventSide = _eventData select 1;
        private _eventFaction = _eventData select 2;
        private _eventAirspace = _eventData select 3;
        private _eventATO = _eventData select 4;

        private _eventROE = _eventATO select 0;
        private _eventHeight = _eventATO select 1;
        private _eventSpeed = _eventATO select 2;
        private _eventMinWeap = _eventATO select 3;
        private _eventMinFuel = _eventATO select 4;
        private _eventRange = _eventATO select 5;
        private _eventDuration = _eventATO select 6;
        private _eventTargets = _eventATO select 7;

        // For radio broadcasts
        private _sideObject = [_side] call ALIVE_fnc_sideTextToObject;
        private _factionName = getText((_eventFaction call ALiVE_fnc_configGetFactionClass) >> "displayName");
        private _hqClass = switch (_sideObject) do {
            case WEST: {
                "BLU"
            };
            case EAST: {
                "OPF"
            };
            case RESISTANCE: {
                "IND"
            };
            default {
                "HQ"
            };
        };
        private _HQ = getText(configFile >> "CfgHQIdentities" >> _hqClass >> "name");

        private _assets = [ALIVE_globalATO,_eventFaction] call ALIVE_fnc_hashGet;
        private _airspaceAssets = [_logic,"airspaceAssets"] call MAINCLASS;

        // Check to see if airspace name or position has been provided
        if (typename _eventAirspace == "ARRAY") then {
            private _tmpAirspace = "";
            {
                if (_eventAirspace inArea _x) exitWith {
                    _tmpAirspace = _x;
                };
            } foreach (_airspaceAssets select 1);
            _eventAirspace = _tmpAirspace;
            _eventData set [3,_eventAirspace];
            [_event,"data",_eventData] call ALiVE_fnc_hashSet;
        };

        // Check to see if request is within airspace, if not use 1st airspace
        if (_eventAirspace == "") then {
            _eventAirspace = (_airspaceAssets select 1) select 0;
            _eventData set [3,_eventAirspace];
            [_event,"data",_eventData] call ALiVE_fnc_hashSet;
        };

        private _airspaceAssets = [_airspaceAssets, _eventAirspace] call ALiVE_fnc_hashGet;
        private _airports = [_logic,"runways"] call MAINCLASS;

        if(_playerRequested) then {
            _playerID = _eventData select 5;
            _requestID = _eventData select 6;
        };

        // DEBUG -------------------------------------------------------------------------------------
        if(_debug) then {
            ["ALIVE ATO %1 - Monitoring Event", _logic] call ALIVE_fnc_dump;
            _event call ALIVE_fnc_inspectHash;
            _requestAnalysis call ALIVE_fnc_inspectHash;
        };
        // DEBUG -------------------------------------------------------------------------------------


        // react according to current event state
        switch(_eventState) do {

            // AI REQUEST ---------------------------------------------------------------------------------------------------------------------------------

            // operation has been requested
            case "requested": {

                private _waitTime = 40;

                // according to the type of operation
                // adjust wait time and setup profiles for operation

                switch(_eventType) do {
                    case "CAP": {
                        _waitTime = WAIT_TIME_CAP;
                    };
                    case "DCA": {
                        _waitTime = WAIT_TIME_DCA;
                    };
                    case "SEAD": {
                        _waitTime = WAIT_TIME_SEAD;
                    };
                    case "CAS": {
                        _waitTime = WAIT_TIME_CAS;
                    };
                    case "STRIKE": {
                        _waitTime = WAIT_TIME_STRIKE;
                    };
                    case "RECCE": {
                        _waitTime = WAIT_TIME_RECCE;
                    };
                };

                // DEBUG -------------------------------------------------------------------------------------
                if(_debug) then {
                    ["ALIVE ATO %4 - Event state: %1 event timer: %2 wait time on event: %3 ",_eventState, (time - _eventTime), _waitTime, _logic] call ALIVE_fnc_dump;
                };
                // DEBUG -------------------------------------------------------------------------------------



                if((time - _eventTime) > _waitTime) then {
                    // Assuming assets are available, find nearest asset that can complete the task, if no appropriate asset report back
                    private _assetAvailable = false;
                    private _opAssets = [];
                    private _selectedAsset = [];
                    private _aircraftType = ["Plane","Helicopter"];
                    private _aircraftRole = "Attack";
                    private _eventPosition = getMarkerPos _eventAirspace;

                    // Based on Op, check what type of aircraft we need
                    switch (_eventType) do {
                        case "CAP";
                        case "DCA" : {
                            _aircraftType = ["Plane"];
                            _aircraftRole = "Fighter";
                        };
                        case "Recce" : {
                            _aircraftType = ["Plane","Helicopter"];
                            _aircraftRole = "Recon";
                        };
                        default {
                            _aircraftType = ["Plane","Helicopter"];
                            _aircraftRole = "Attack";
                        };
                    };

                    // Check airspace assets first
                    {
                        private _profileID = _x;
                        private _tmpType = [[_assets,_profileID] call ALiVE_fnc_hashGet,"vehicleClass"] call ALiVE_fnc_hashGet;
                        if ( {_tmpType iskindof _x} count _aircraftType > 0) then {
                            _opAssets pushback _x;
                        };
                    } foreach _airspaceAssets;

                    // ["ALIVE ATO %1 OP ASSETS: %2", _logic, _opAssets] call ALiVE_fnc_dump;

                    // Get an asset from another airspace if it is CAS
                    if (count _opAssets == 0 && _eventType == "CAS") then {

                        {
                            If (_x != _eventAirspace) then {
                                {
                                    private _tmpType = [[_assets,_x] call ALiVE_fnc_hashGet,"vehicleClass"] call ALiVE_fnc_hashGet;
                                    if ( {_tmpType iskindof _x} count _aircraftType > 0) then {
                                        _opAssets pushback _x;
                                    };
                                } foreach ([[_logic,"airspaceAssets"] call MAINCLASS, _x] call ALiVE_fnc_hashGet);
                            };
                        } foreach ([_logic,"airspaceAssets"] call MAINCLASS select 1);
                    };

                    // Check to see if they are available - check damage, fuel, ammo, parked or on CAP
                    if (count _opAssets > 0) then {

                        {
                            private _profileID = _x;
                            private _profile = [ALIVE_profileHandler, "getProfile",_profileID] call ALIVE_fnc_profileHandler;
                            private _exit = false;

                            if !(isNil "_profile") then {
                                private _aircraft = [_assets,_x] call ALiVE_fnc_hashGet;

                                // check aircraft has the correct role
                                private _aircraftRoles = [_aircraft,"roles"] call ALiVE_fnc_hashGet;
                                if (_aircraftRole in _aircraftRoles) then {
                                    private _position = [_aircraft,"startPos"] call ALiVE_fnc_hashGet;
                                    private _currentOp = [_aircraft,"currentOp",""] call ALiVE_fnc_hashGet;
                                    private _profileType = [_profile, "type"] call ALiVE_fnc_hashGet;
                                    private _crewAvailable = true;

                                    if (_profileType == "entity") then {
                                        private _profileVehID = ([_profile, "vehiclesInCommandOf"] call ALiVE_fnc_hashGet) select 0;
                                        _profile = [ALIVE_profileHandler, "getProfile",_profileVehID] call ALIVE_fnc_profileHandler;
                                    };

                                    private _active = [_profile,"active"] call ALiVE_fnc_hashGet;
                                    private _damage = [_profile, "damage"] call ALiVE_fnc_hashGet;
                                    if (count _damage == 0) then {
                                        _damage = 0;
                                    } else {
                                        // Calculate % of damage
                                        private _curDamage = 0;
                                        {
                                            _curDamage = _curDamage + (_x select 1);
                                        } foreach _damage;
                                        if (_curDamage == 0) then {
                                            _damage = 0;
                                        } else {
                                            _damage = _curDamage / count _damage;
                                        };
                                    };

                                    private _fuel = [_profile, "fuel"] call ALiVE_fnc_hashGet;
                                    private _currentPosition = [_profile, "position"] call ALiVE_fnc_hashGet;

                                    private _ammo = [_profile, "ammo"] call ALiVE_fnc_hashGet;
                                    if (count _ammo == 0) then {
                                            _ammo = 1;
                                    } else {
                                        // Calculate % of ammo
                                        private _avail = 0;
                                        {
                                            _avail = _avail + ((_x select 1)/(_x select 2));
                                        } foreach _ammo;
                                        _ammo = _avail / count _ammo;
                                    };

                                    if (_active) then {
                                        private _vehicleObj = [_profile, "vehicle"] call ALiVE_fnc_hashGet;
                                        _damage = damage _vehicleObj;
                                        _fuel = fuel _vehicleObj;
                                        _currentPosition = getposATL _vehicleObj;
                                    };

                                    // diag_log format["ALIVE ATO %4 %5 F:%1, A:%2, D:%3, Dist:%6,",_fuel, _ammo, _damage, _logic, _profileID, _position distance _currentPosition];

                                    // Check crew are alive if not UAV

                                    if !(([_profile,"vehicleClass"] call ALiVE_fnc_hashGet) isKindOf "UAV") then {
                                        private _crewID = [_aircraft,"crewID"] call ALiVE_fnc_hashGet;
                                        private _crewProfile = [ALIVE_profileHandler, "getProfile",_crewID] call ALIVE_fnc_profileHandler;
                                        if (isNil "_crewProfile") then {
                                            _crewAvailable = false;
                                        };
                                    };

                                    // If an asset is parked or flying a CAP (and the request is not CAP) then the aircraft is available (or if CAS is requested)
                                    if (_crewAvailable) then {

                                        // Get active event type
                                        if (_currentOp != "") then {
                                            //Retrieve event data
                                            private _currentEvent = [_eventQueue, _currentOp,[]] call ALIVE_fnc_hashGet;
                                            private _currentOpState = [_currentEvent, "state",""] call ALIVE_fnc_hashGet;
                                            if !(_currentOpState in ["aircraftLanding","aircraftReturnWait","aircraftStart"]) then {
                                                _currentOp = [_currentEvent, "data"] call ALIVE_fnc_hashGet select 0;
                                            } else {
                                                // Aircraft is starting/landing, so not available yet, set fuel measurement to zero
                                                _fuel = 0;
                                            };
                                        };

                                        // Don't reroute an aircraft twice
                                        if !([_aircraft,"reroute", false] call ALiVE_fnc_hashGet) then {

                                            // If parked and not doing anything add, if on CAP and request is DCA,CAS,SEAD then reroute, if its CAS and currently on CAS don't reroute - make sure aircraft is fit for purpose
                                            if ( ( ((_position distance _currentPosition < 15) && _currentOp == "") || (_currentOp == "CAP" && _eventType in ["DCA","CAS","SEAD"]) || (_currentOp != "CAS" && _eventType == "CAS") ) && (_fuel > _eventMinFuel && _ammo > _eventMinWeap && _damage < 0.5)) then {

                                                [_aircraft,"currentPos",_currentPosition] call ALiVE_fnc_hashSet;
                                                [_aircraft,"profileID",_x] call ALiVE_fnc_hashSet;
                                                _selectedAsset pushback _aircraft;

                                                // If the aircraft is on a CAP and not in the process of landing, send it to intercept
                                                if (_currentOp == "CAP" && _eventType == "DCA") then {
                                                    _selectedAsset = [_aircraft];
                                                    _exit = true;
                                                };
                                            };
                                        };
                                    } else {
                                        // If crew is not available, ensure LOGCOM request goes in
                                    };
                                };
                            };
                            if (_exit) exitWith {};
                        } foreach _opAssets;

                        if (count _selectedAsset > 0) then {

                            // Get target position
                            if (_eventType != "CAP") then {

                                // Spawn any event targets
                                {
                                    if (typeName _x == "STRING") then {
                                         private _targetProfile = [ALiVE_profileHandler, "getProfile", _x] call ALiVE_fnc_ProfileHandler;
                                         if !(isNil "_targetProfile") then {
                                            [_targetProfile,"spawnType",["preventDespawn"]] call ALiVE_fnc_hashSet;

                                            private _active = [_targetProfile,"active"] call ALiVE_fnc_hashGet;
                                            if !(_active) then {
                                                 private _type = [_targetProfile,"type"] call ALiVE_fnc_hashGet;
                                                 if (_type == "entity") then {
                                                    [_targetProfile,"spawn"] call ALiVE_fnc_profileEntity;
                                                 } else {
                                                    [_targetProfile,"spawn"] call ALiVE_fnc_profileVehicle;
                                                    // diag_log format["SPAWNING TARGET: %1",_x];
                                                };
                                            };
                                        };
                                    };
                                } foreach _eventTargets;

                                // Work out distance to first target
                                if (typeName (_eventTargets select 0) == "OBJECT") then {
                                    _eventPosition = position (_eventTargets select 0);
                                } else {
                                    private _targetProfile = [ALiVE_profileHandler, "getProfile", (_eventTargets select 0)] call ALiVE_fnc_ProfileHandler;
                                    _eventPosition = [_targetProfile,"position"] call ALiVE_fnc_hashGet;
                                };
                            };

                            // Sort by distance
                            _selectedAsset = ([_selectedAsset,[],{_eventPosition distance ([_x,"currentPos"] call ALiVE_fnc_hashGet)},"ASCEND"] call ALiVE_fnc_SortBy) select 0;
                            _assetAvailable = true;

                            // DEBUG -------------------------------------------------------------------------------------
                            if(_debug) then {
                                _selectedAsset call ALIVE_fnc_inspectHash;
                            };

                        };
                    };

                    // If asset is available set data needed
                    if(_assetAvailable) then {

                        private _profileID = [_selectedAsset,"profileID"] call ALiVE_fnc_hashGet;
                        private _startPosition = [_selectedAsset,"startPos"] call ALiVE_fnc_hashGet;
                        private _vehicleClass = [_selectedAsset,"vehicleClass"] call ALiVE_fnc_hashGet;
                        private _currentPosition = [_selectedAsset,"currentPos"] call ALiVE_fnc_hashGet;
                        private _currentOp = [_selectedAsset,"currentOp",""] call ALiVE_fnc_hashGet;
                        private _parked = false;
                        private _takeoff = false;

                        // Get start position
                        if (_startPosition distance _currentPosition < 15) then {
                            _parked = true;
                        };

                        if (_parked) then {
                            // players near check
                            _playersInRange = [_startPosition, 1500] call ALiVE_fnc_anyPlayersInRange;

                            // if players are in visible range and aircraft parked, start takeoff procedure
                            if(_playersInRange > 0) then {
                                _takeoff = true;
                            };
                        };

                        // Add entity profile ID
                        _eventFriendlyProfiles pushback _profileID;

                        // Log details
                        ["AI ATO Side: %1, Faction: %2, Asset: %3, Profiles: %8, Start: %4, Position: %5, ATO: %6, Targets: %7", _eventSide, _eventFaction, _vehicleClass, _currentPosition, _eventPosition, _eventType, _eventTargets,_eventFriendlyProfiles] call ALiVE_fnc_dump;

                        // DEBUG -------------------------------------------------------------------------------------
                        if(_debug) then {
                            switch(_eventType) do {
                                case "CAP": {
                                    [_logic, "createMarker", [_currentPosition,_eventSide,"CAP ASSET",0]] call MAINCLASS;
                                    [_logic, "createMarker", [_eventPosition,_eventSide,"CAP RADIUS",_eventRange]] call MAINCLASS;
                                };
                                default {
                                    [_logic, "createMarker", [_currentPosition,_eventSide,"ATO ASSET",0]] call MAINCLASS;
                                    [_logic, "createMarker", [_eventPosition,_eventSide,"ATO TARGET",0]] call MAINCLASS;
                                };

                            };
                        };
                        // DEBUG -------------------------------------------------------------------------------------

                        // Set current op for asset

                        // Check for existing OP?
                        if (_currentOp != "") then {

                            //
                            if (_debug) then {
                                ["ALIVE ATO %4 Rerouting %1 (%2) for new request %3", _profileID, _currentOp, _eventType, _logic] call ALiVE_fnc_dump;
                            };

                            // Radio Broadcast

                            // Vehicle is active and doing something, so remove all existing waypoints in prep for new request
                            private _profile = [ALIVE_profileHandler, "getProfile",_profileID] call ALIVE_fnc_profileHandler;
                            if (!isNil "_profile") then {
                                private _vehicleObj = [_profile, "vehicle",objnull] call ALiVE_fnc_hashGet;
                                private _grp = group _vehicleObj;
                                while {(count (waypoints _grp)) > 0} do
                                {
                                    deleteWaypoint ((waypoints _grp) select 0);
                                };
                            };

                            [_selectedAsset,"reroute",true] call ALiVE_fnc_hashSet;

                            // Remove old event so aircraft can switch to new tasking
                            // set state to event complete
                            private _oldEvent = [_eventQueue,_currentOp] call ALiVE_fnc_hashGet;
                            [_oldEvent, "state", "eventComplete"] call ALIVE_fnc_hashSet;
                            [_eventQueue, _eventID, _oldEvent] call ALIVE_fnc_hashSet;
                        };

                        // Update assets
                        [_selectedAsset,"currentOp",_eventID] call ALiVE_fnc_hashSet;
                        [_assets,_profileID,_selectedAsset] call ALiVE_fnc_hashSet;
                        [_logic,"assets",_assets] call MAINCLASS;

                        _eventData pushback _eventPosition;
                        _eventData pushback _takeoff;

                        [_event, "friendlyProfiles", _eventFriendlyProfiles] call ALIVE_fnc_hashSet;

                        // get the profile IDs for eventTargets (and convert any profiles to real targets)
                        _eventEnemyProfiles = [];
                        {
                            if (typeName _x == "OBJECT") then {
                                if (_x getVariable ["profileID",""] != "") then {
                                    _eventEnemyProfiles pushback (_x getVariable "profileID");
                                };
                            } else {
                                _eventEnemyProfiles pushback _x;
                                private _targetProfile = [ALiVE_profileHandler, "getProfile", _x] call ALiVE_fnc_ProfileHandler;
                                if !(isNil "_targetProfile") then {
                                    private _type = [_targetProfile,"type"] call ALiVE_fnc_hashGet;
                                    // _targetProfile call ALIVE_fnc_inspectHash;
                                    private _vehicle = objNull;
                                    if (_type == "entity") then {
                                        _vehicle = [_targetProfile,"leader"] call ALiVE_fnc_hashGet;
                                    } else {
                                        _vehicle = [_targetProfile,"vehicle"] call ALiVE_fnc_hashGet;
                                    };
                                    _eventTargets set [_foreachIndex, _vehicle];
                                };
                            };
                        } foreach _eventTargets;

                        [_event, "enemyProfiles", _eventEnemyProfiles] call ALIVE_fnc_hashSet;

                        [_event, "data", _eventData] call ALIVE_fnc_hashSet;

                        // update the state of the event
                        // next state is aircraftStart
                        [_event, "state", "aircraftStart"] call ALIVE_fnc_hashSet;

                        // dispatch event
                        private _logEvent = [format['ATO_%1',_eventType], [_eventPosition,_eventFaction,_eventSide,_eventID],"air tasking orders"] call ALIVE_fnc_event;
                        [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;

                        [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;

                    }else{

                        // An appropriate aircraft is not available to do the op
                        // DEBUG -------------------------------------------------------------------------------------
                        if(_debug) then {
                            ["ALIVE ATO %2 - Air Tasking request denied, Joint Forces Air Component Commander for %1 has no appropriate available air assets", _eventFaction, _logic] call ALIVE_fnc_dump;
                        };
                        // DEBUG -------------------------------------------------------------------------------------

                        //Radio Broadcast
                        private _message = format[localize "STR_ALIVE_ATO_REQUEST_DENIED", _HQ, _eventType, mapGridPosition _eventPosition];
                        // send a message to all side players from HQ
                        private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                        [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

                        // nothing to do so cancel..
                        [_logic, "removeEvent", _eventID] call MAINCLASS;
                    };
                };
            };

            case "aircraftStart": {

                private _eventPosition = _eventData select 5;
                private _takeoff = _eventData select 6;

                private _aircraftID = _eventFriendlyProfiles select 0;
                private _aircraft = [_assets,_aircraftID] call ALiVE_fnc_hashGet;

                private _profileID = [_aircraft,"profileID"] call ALiVE_fnc_hashGet;
                private _startPosition = [_aircraft,"startPos"] call ALiVE_fnc_hashGet;
                private _startDir = [_aircraft,"startDir"] call ALiVE_fnc_hashGet;
                private _vehicleClass = [_aircraft,"vehicleClass"] call ALiVE_fnc_hashGet;
                private _isVTOL = [_vehicleClass] call ALiVE_fnc_isVTOL;
                private _currentPosition = [_aircraft,"currentPos"] call ALiVE_fnc_hashGet;
                private _aircraftReady = [_aircraft,"ready",false] call ALiVE_fnc_hashGet;
                private _isOnCarrier = [_aircraft,"isOnCarrier",false] call ALiVE_fnc_hashGet;
                private _isPlane = _vehicleClass iskindof "Plane" && ((_isVTOL mod 2) == 0);

                private _count = [_logic, "checkEvent", _event] call MAINCLASS;

                if(_count == 0) exitWith {
                    private _className = getText(configFile >> "CfgVehicles" >> _vehicleClass >> "displayName");
                    private _message = format[localize "STR_ALIVE_ATO_AIRCRAFT_LOST", _HQ, _className, _eventType];
                    // send a message to all side players from HQ
                    private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                    [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

                    if(_playerRequested) then {
                        private _logEvent = ['ATO_RESPONSE', [_requestID,_playerID],"Logistics","REQUEST_LOST"] call ALIVE_fnc_event;
                        [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;
                    };
                    // set state to event complete
                    [_event, "state", "eventComplete"] call ALIVE_fnc_hashSet;
                    [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;

                    private _airportID = [_aircraft,"airportID",[_startPosition] call ALiVE_fnc_getNearestAirportID] call ALiVE_fnc_hashGet;
                    // if plane check to see if runway is busy, wait
                    private _airportBusy = [_airports, _airportID] call ALiVE_fnc_hashGet;

                    if (_airportBusy) then {

                        // Mark airport as no longer busy
                        [_airports, _airportID, false] call ALiVE_fnc_hashSet;
                        [_logic,"runways",_airports] call MAINCLASS;
                    };

                };

                if !(_aircraftReady) then {

                    // Prep aircraft (launch if not spawned)
                    if (_takeoff) then {

                        private _airportBusy = false;
                        private _airportID = 0;
                        private _UCAV = false;
                        private _catapult = [];

                        // If runway takeoff, handle runway/catapult deconfliction
                        if (_isPlane) then {
                            _airportID = [_aircraft,"airportID",[_startPosition] call ALiVE_fnc_getNearestAirportID] call ALiVE_fnc_hashGet;
                            // if plane check to see if runway is busy, wait
                            _airportBusy = [_airports, _airportID] call ALiVE_fnc_hashGet;

                            // Check catapult is free
                            if (surfaceIsWater _startPosition && _isOnCarrier) then {
                                _isUCAV = if (_vehicleClass isKindOf "B_UAV_05_F") then {true} else {false};
                                _catapult = [_startPosition, _isUCAV] call ALiVE_fnc_getNearestCatapult;
                                if !(isNil "_catapult") then {
                                    private _position = [_catapult, "position"] call ALiVE_fnc_hashGet;
                                    private _nearbyObj = nearestObjects [_position, ["Plane"], 3];
                                    if (count _nearbyObj > 0) then {
                                        // diag_log ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>. CATAPULT BUSY <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<";
                                        _airportBusy = true;
                                    };
                                };
                            };
                        };

                        if (!_airportBusy || !_isPlane) then {

                                // Play scramble alarm
                                [_startPosition] spawn {
                                    private _pos = _this select 0;
                                    private _alarm = createSoundSource ["Sound_AirRaidSiren", _pos, [], 0]; //starts alarm
                                    sleep 30;
                                    deleteVehicle _alarm; //stops alarm
                                };

                                private _taxiPosition = +_startPosition;
                                private _taxiDir = 0;

                                // Get taxi or catapult position
                                If (_isPlane) then {
                                    // Mark airport as busy
                                    [_airports, _airportID, true] call ALiVE_fnc_hashSet;
                                    [_logic,"runways",_airports] call MAINCLASS;

                                    // Get Taxi position
                                    private _taxiPositions = [_airportID, "ilsTaxiIn",4] call ALiVE_fnc_getAirportTaxiPos;
                                    _taxiPosition = [_taxiPositions select 0, _taxiPositions select 1];
                                    _taxiDir = _taxiPosition getDir [_taxiPositions select 2, _taxiPositions select 3];

                                    // Check to see if we are over water, assume aircraft carrier, check for catapult
                                    if (surfaceIsWater _taxiPosition && _isOnCarrier) then {
                                        _taxiPosition = +_startPosition;
                                        if !(isNil "_catapult") then {
                                            _taxiPosition = [_catapult, "position", _taxiPosition] call ALiVE_fnc_hashGet;

                                            private _part = [_catapult, "part"] call ALiVE_fnc_hashGet;
                                            _taxiDir = [_catapult, "dirOffset", direction _part] call ALiVE_fnc_hashGet;
                                            _taxiDir = [(direction _part) + 180 - _taxiDir] call ALiVE_fnc_modDegrees;

                                            [_aircraft,"catapult",_catapult] call ALiVE_fnc_hashSet;
                                        };
                                    };
                                };

                                // If not active then assign crew and spawn else move crew into aircraft
                                private _profile = [ALIVE_profileHandler, "getProfile",_profileID] call ALIVE_fnc_profileHandler;
                                private _crewID = [_aircraft,"crewID",""] call ALiVE_fnc_hashGet;
                                private _crewProfile = [ALIVE_profileHandler, "getProfile",_crewID] call ALIVE_fnc_profileHandler;

                                if (isNil "_crewProfile" && !(_vehicleClass isKindOf "UAV")) exitWith {
                                    // abort mission
                                    [_event, "state", "eventComplete"] call ALIVE_fnc_hashSet;
                                    [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;

                                    // unlock runway
                                    if (_isPlane) then {
                                        [_logic, "unlockRunway", _airportID] call MAINCLASS;
                                    };

                                    // reset aircraft Op
                                    [_aircraft,"currentOp",""] call ALiVE_fnc_hashSet;
                                    [_assets,_profileID,_aircraft] call ALiVE_fnc_hashSet;
                                    [_logic,"assets",_assets] call MAINCLASS;
                                };

                                // DEBUG -------------------------------------------------------------------------------------
                                if(_debug) then {
                                    ["ALIVE ATO %3 - Preparing aircraft (%1 - %2)", _profileID, _vehicleClass, _logic] call ALIVE_fnc_dump;
                                };
                                // DEBUG -------------------------------------------------------------------------------------

                                if !([_profile,"active"] call ALiVE_fnc_hashGet) then {

                                    // Assign crew if not UAV
                                    if !(_vehicleClass isKindOf "UAV") then {
                                        [_crewProfile,_profile] call ALIVE_fnc_createProfileVehicleAssignment;
                                    };

                                    // Spawn aircraft and if UAV add crew
                                    [_profile,"spawnType",["preventDespawn"]] call ALiVE_fnc_profileVehicle;
                                    if (_isOnCarrier) then {
                                        _taxiPosition = ASLtoATL _taxiPosition;
                                    };

                                    // diag_log format["ALIVE ATO %1 SPAWNING AIRCRAFT %2 AT POSITION %3", _logic, _profileID, _taxiPosition];
                                    [_profile,"position",_taxiPosition] call ALiVE_fnc_profileVehicle;
                                    [_profile,"despawnPosition", _taxiPosition] call ALiVE_fnc_profileVehicle;
                                    [_profile,"direction",_taxiDir] call ALiVE_fnc_profileVehicle;
                                    [_profile,"spawn"] call ALiVE_fnc_profileVehicle;
                                    if (_debug) then {
                                        ["ATO: Spawning"] call ALiVE_fnc_dump;
                                        _profile call ALIVE_fnc_inspectHash;
                                    };

                                } else {

                                    // Make sure crew are active
                                    if (!(_vehicleClass isKindOf "UAV") && {!([_crewProfile,"active"] call ALiVE_fnc_hashGet)} ) then {

                                        [_crewProfile,"spawn"] call ALiVE_fnc_profileEntity;
                                        if (_debug) then {
                                            ["ATO: Spawning crew (for aircraft already spawned)"] call ALiVE_fnc_dump;
                                            _crewProfile call ALIVE_fnc_inspectHash;
                                        };
                                    };

                                    // Get vehicle
                                    private _vehicleObj = [_profile,"vehicle"] call ALiVE_fnc_hashGet;

                                    if !(_vehicleClass isKindOf "UAV") then {
                                        // Move crew into aircraft
                                        private _group = [_crewProfile,"group"] call ALiVE_fnc_hashGet;

                                        // DEBUG -------------------------------------------------------------------------------------
                                        if(_debug) then {
                                            ["ALIVE ATO %3 - MOVING CREW (%4) TO AIRCRAFT (%1 - %2)", _profileID, _vehicleClass, _logic, _group] call ALIVE_fnc_dump;
                                        };
                                        // DEBUG -------------------------------------------------------------------------------------

                                        // diag_log _group;
                                        _group addVehicle _vehicleObj;

                                        if (_isOnCarrier) then { // AI can't run to plane on carrier deck
                                            {
                                                _x moveInAny _vehicleObj;
                                            } foreach (units _group);
                                        } else {
                                            (units _group) orderGetIn true;
                                        };
                                    };

                                    // Move aircraft to start position
                                    if (_isPlane) then {
                                        // Move the plane to ilsTaxiIn position or nearest catapult on carrier
                                        // diag_log format["ALIVE ATO %1 MOVING AIRCRAFT %2 TO POSITION %3",_logic, _profileID, _taxiPosition];
                                        // _profile call ALIVE_fnc_inspectHash;
                                        if (surfaceIsWater _taxiPosition && _isOnCarrier) then {
                                            _vehicleObj setPosASL _taxiPosition; // might need to adjust for sea level changes?

                                        } else {
                                            _vehicleObj setPos _taxiPosition;
                                        };
                                        _vehicleObj setDir _taxiDir;
                                    };
                                };

                                if (_vehicleClass isKindOf "UAV") then {
                                    private _vehicleObj = [_profile,"vehicle"] call ALiVE_fnc_hashGet;
                                    // Add crew
                                    createVehicleCrew _vehicleObj;
                                };

                                // Mark aircraft as ready
                                _aircraftReady = true;
                                [_aircraft,"ready",true] call ALiVE_fnc_hashSet;

                        } else {
                            // Airport is busy
                            if (_debug) then {
                                ["ALIVE ATO %3 Airport busy %1 %2",_airportID,_airportBusy, _logic] call ALiVE_fnc_dump;
                            };
                        };

                    } else {
                        // if parked assign crew to vehicle if necessary, if at home move to ilsTaxiOut position at 300 feet, spawn aircraft at speed
                        if (_startPosition distance _currentPosition < 15) then {

                            private _isPlane = _vehicleClass iskindof "Plane" && ((_isVTOL mod 2) == 0);
                            private _profile = [ALIVE_profileHandler, "getProfile",_profileID] call ALIVE_fnc_profileHandler;

                            // If not active and not a UAV then launch, else go take off normally.
                            if !([_profile,"active"] call ALiVE_fnc_hashGet) then {

                                private _crewID = [_aircraft,"crewID",""] call ALiVE_fnc_hashGet;
                                private _crewProfile = [ALIVE_profileHandler, "getProfile",_crewID] call ALIVE_fnc_profileHandler;

                                if (isNil "_crewProfile" && !(_vehicleClass isKindOf "UAV")) exitWith {
                                    // abort mission
                                    [_event, "state", "eventComplete"] call ALIVE_fnc_hashSet;
                                    [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;

                                    // unlock runway
                                    if (_isPlane) then {
                                        [_logic, "unlockRunway", _airportID] call MAINCLASS;
                                    };

                                    // reset aircraft Op
                                    [_aircraft,"currentOp",""] call ALiVE_fnc_hashSet;
                                    [_assets,_profileID,_aircraft] call ALiVE_fnc_hashSet;
                                    [_logic,"assets",_assets] call MAINCLASS;
                                };

                                // Assign crew to aircraft
                                if !(_vehicleClass isKindOf "UAV") then {
                                    // Assign crew
                                    [_crewProfile,_profile] call ALIVE_fnc_createProfileVehicleAssignment;
                                };

                                private _taxiPosition = +_startPosition;
                                private _taxiDir = [_profile,"direction"] call ALiVE_fnc_hashGet;
                                _taxiPosition set [2,300];

                                if (_isPlane) then {
                                    // Set position relative to TaxiOff (but 300m up)
                                    private _airportID = [_aircraft,"airportID",[_startPosition] call ALiVE_fnc_getNearestAirportID] call ALiVE_fnc_hashGet;
                                    private _taxiPositions = [_airportID, "ilsTaxiOff",4] call ALiVE_fnc_getAirportTaxiPos;
                                    _taxiPosition = [_taxiPositions select 0, _taxiPositions select 1, 300];
                                    _taxiDir = _taxiPosition getDir [_taxiPositions select 2, _taxiPositions select 3, _taxiPosition select 2];
                                };

                                if (surfaceIsWater _taxiPosition) then {
                                    _taxiPosition set [2, 600];
                                };

                                // Set profile information
                                [_profile,"engineOn",true] call ALiVE_fnc_profileVehicle;
                                [_profile,"position",_taxiPosition] call ALiVE_fnc_profileVehicle;
                                [_profile,"despawnPosition", _taxiPosition] call ALiVE_fnc_profileVehicle;
                                [_profile,"direction",_taxiDir] call ALiVE_fnc_profileVehicle;
                                [_profile,"spawnType",["preventDespawn"]] call ALiVE_fnc_profileVehicle;

                                // Spawn aircraft in air
                                [_profile,"spawn"] call ALiVE_fnc_profileVehicle;
                                if (_debug) then {
                                    ["ATO: Spawning"] call ALiVE_fnc_dump;
                                    _profile call ALIVE_fnc_inspectHash;
                                };

                                if (_vehicleClass isKindOf "UAV") then {
                                    private _vehicleObj = [_profile,"vehicle"] call ALiVE_fnc_hashGet;
                                    // Add crew
                                    createVehicleCrew _vehicleObj;
                                };

                                // Set Aircraft as ready for mission
                                _aircraftReady = true;
                                [_aircraft,"ready",true] call ALiVE_fnc_hashSet;
                            } else {

                                // If active, needs to takeoff properly? or move to height?
                                _eventData set [6,true];
                                [_event, "data", _eventData] call ALIVE_fnc_hashSet;

                            };
                        } else {
                            // else plane should be active with crew and flying and ready
                            _aircraftReady = true;
                            [_aircraft,"ready",true] call ALiVE_fnc_hashSet;
                        };
                    };

                } else {

                    // DEBUG -------------------------------------------------------------------------------------
                    if(_debug) then {
                        ["ALIVE ATO %3 - aircraft (%1 - %2) is READY.", _profileID, _vehicleClass, _logic] call ALIVE_fnc_dump;
                    };
                    // DEBUG -------------------------------------------------------------------------------------
                    // Get vehicle to check for crew
                    private _vehProfile = [ALIVE_profileHandler, "getProfile",_profileID] call ALIVE_fnc_profileHandler;
                    private _vehicle = [_vehProfile,"vehicle"] call ALiVE_fnc_hashGet;

                    private _grp = group _vehicle;

                    //Radio Broadcast
                    private _callsign = groupID _grp;

                    if (_callsign != "") then {
                        private _message = format[localize "STR_ALIVE_ATO_START", _HQ, _callsign, _eventType, mapGridPosition _eventPosition];
                        // send a message to all side players from HQ
                        private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                        [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;
                    };

                    // Wait for driver or time expiration
                    if ( !(isNUll (driver _vehicle)) || {time > (_eventTime + ((_eventDuration/3)*60))} || {_isOnCarrier}) then {

                        // Check driver is onboard if not put the crew in there
                        if (isNUll (driver _vehicle) || {time > (_eventTime + ((_eventDuration/3)*60))} ) then {
                            if (_debug) then {
                                ["ALIVE ATO %3 - aircraft (%1 - %2) is waiting on the pilot in group %4 with the units: %5.", _profileID, typeof _vehicle, _logic, _grp, units _grp] call ALIVE_fnc_dump;
                            };
                            {
                                _x moveInAny _vehicle;
                            } foreach (units _grp);
                            if (_vehicle isKindOf "UAV") then {
                                createVehicleCrew _vehicle;
                            };
                        };

                        // Ok driver should be in vehicle now
                        if !(isNUll (driver _vehicle)) then {

                            // DEBUG -------------------------------------------------------------------------------------
                            if(_debug) then {
                                ["ALIVE ATO %3 - aircraft (%1 - %2) is LAUNCHING.", _profileID, _vehicleClass, _logic] call ALIVE_fnc_dump;
                            };
                            // DEBUG -------------------------------------------------------------------------------------

                            // Handle Carrier takeoff
                            If ( _isOnCarrier && _takeoff && _isPlane ) then {
                                // Get the engine started
                                _vehicle engineOn true;
                                // Get the catapult
                                private _catapult = [_aircraft,"catapult",[position _vehicle] call ALiVE_fnc_getNearestCatapult] call ALiVE_fnc_hashGet;
                                // Launch the aircraft
                                private _result = [_vehicle, _catapult] call ALiVE_fnc_catapultLaunch;
                                if (_debug) then {
                                    ["ALIVE ATO %3 IS CATAPULT LAUNCHING AIRCRAFT %1 with result %2", _profileID, _result, _Logic] call ALIVE_fnc_dump;
                                };
                            };

                            // Make sure the group are not quiesced since last op
                            _grp enableAttack true;
                            {
                                _x enableAI "TARGET";
                                _x enableAI "AUTOTARGET";
                                _x setCombatMode _eventROE;
                            } foreach units _grp;


                            private _wpPosition = _eventPosition;

                            if (_eventType in ["CAS","DCA","SEAD","Strike"] && count _eventTargets > 0) then {
                                _wpPosition = _eventTargets select 0;
                            };

                            private _wp = _grp addWaypoint [_wpPosition,0,1,"ATO"];
                            _wp setWaypointSpeed _eventSpeed;
                            _wp setWaypointBehaviour "AWARE";
                            _wp setWaypointCombatMode _eventROE;
                            // _wp setWaypointStatements ["true","if (alive this) then {deleteWaypoint [group this, currentWaypoint (group this)]}"];

                            switch (_eventType) do {
                                case "Recce": {
                                    // Loiter waypoint
                                    _wp setWaypointType "LOITER";
                                    _wp setWaypointLoiterType "CIRCLE_L";
                                    _wp setWaypointLoiterRadius (_eventRange * 0.9);
                                    _wp setWaypointTimeout [_eventDuration,_eventDuration,_eventDuration];
                                    // _wp setWaypointCompletionRadius _eventRange;
                                };
                                case "CAS": {
                                    // SAD waypoint, if targets then DESTROY
                                    if (count _eventTargets == 1) then {
                                        _wp setWaypointType "DESTROY";
                                        _grp reveal (_eventTargets select 0);
                                    } else {
                                        _wp setWaypointType "SAD";
                                        _wp setWaypointPosition [position (_eventTargets select 0), 0];
                                        _wp setWaypointTimeout [_eventDuration,_eventDuration,_eventDuration];
                                    };
                                };
                                case "DCA";
                                case "SEAD";
                                case "Strike": {
                                    // DESTROY
                                    if (_debug) then {
                                        ["ALIVE ATO EVENT TARGET: %1 (%2)", _eventTargets select 0, typeName (_eventTargets select 0)] call ALiVE_fnc_dump;
                                    };
                                    _wp setWaypointType "DESTROY";
                                    // _wp setWaypointTimeout [_eventDuration,_eventDuration,_eventDuration];
                                    _grp reveal (_eventTargets select 0);

                                };
                                default {
                                    // CAP
                                    _wp setWaypointType "LOITER";
                                    _wp setWaypointLoiterType "CIRCLE";
                                    _wp setWaypointLoiterRadius (_eventRange * 0.7);
                                    _wp setWaypointTimeout [_eventDuration,_eventDuration,_eventDuration];
                                    _wp setWaypointBehaviour "SAFE";
                                    // _wp setWaypointCompletionRadius _eventRange;
                                };
                            };

                            _vehicle flyInHeight _eventHeight;

                            // dispatch event
                            private _logEvent = ['ATO_DESTINATION', [_eventPosition,_eventFaction,_side,_eventID],"air tasking orders"] call ALIVE_fnc_event;
                            [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;

                            // respond to player request
                            if(_playerRequested) then {
                                private _logEvent = ['ATO_RESPONSE', [_requestID,_playerID],"air tasking orders","REQUEST_ENROUTE"] call ALIVE_fnc_event;
                                [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;
                            };

                            [_event, "state", "aircraftTravel"] call ALIVE_fnc_hashSet;
                            [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;
                        } else {
                            // Waiting on pilot to be ready
                            // DEBUG -------------------------------------------------------------------------------------
                            if(_debug) then {
                                ["ALIVE ATO %3 - Requested aircraft (%1 - %2) is STILL waiting on the pilot.", _profileID, typeof _vehicle, _logic] call ALIVE_fnc_dump;
                            };
                            // DEBUG -------------------------------------------------------------------------------------

                            // If we are still short of a driver and time is running out, can the request? Reroute?
                            if (time > (_eventTime + ((_eventDuration/3)*60))) then {
                                // DEBUG -------------------------------------------------------------------------------------
                                if(_debug) then {
                                    ["ALIVE ATO %3 - Requested aircraft (%1 - %2) is OUT OF TIME waiting on the pilot.", _profileID, typeof _vehicle, _logic] call ALIVE_fnc_dump;
                                };
                                // DEBUG -------------------------------------------------------------------------------------

                                //Move back to original position
                                _vehicle setDir ([_aircraft,"startDir"] call ALiVE_fnc_hashGet);

                                if !(_isOnCarrier) then {
                                    _vehicle setpos _startPosition;
                                } else {
                                    _vehicle setposATL [_startPosition select 0, _startPosition select 1, (_startPosition select 2) + 1];
                                };

                                // remove currentOp from vehicle
                                [_aircraft,"currentOp",""] call ALiVE_fnc_hashSet;
                                [_assets,_aircraftID,_aircraft] call ALiVE_fnc_hashSet;


                                // Unlock runway
                                if (_vehicleClass iskindof "Plane" && ((_isVTOL mod 2) == 0) ) then {
                                    private _airportID = [_aircraft,"airportID",[_startPosition] call ALiVE_fnc_getNearestAirportID] call ALiVE_fnc_hashGet;
                                    [_logic, "unlockRunway", _airportID] call MAINCLASS;
                                };

                                // set state to event complete
                                if(_playerRequested) then {
                                    private _logEvent = ['ATO_RESPONSE', [_requestID,_playerID],"Logistics","REQUEST_LOST"] call ALIVE_fnc_event;
                                    [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;
                                };
                                [_event, "state", "eventComplete"] call ALIVE_fnc_hashSet;
                                [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;
                            };

                        };

                    } else {
                        // Waiting on pilot to be ready
                        // DEBUG -------------------------------------------------------------------------------------
                        if(_debug) then {
                            ["ALIVE ATO %3 - Requested aircraft (%1 - %2) is waiting on the pilot.", _profileID, typeof _vehicle, _logic] call ALIVE_fnc_dump;
                        };
                        // DEBUG -------------------------------------------------------------------------------------
                    };
                };

                // Set aircraft state in case we are waiting for the pilot
                [_assets,_aircraftID,_aircraft] call ALiVE_fnc_hashSet;
            };

            case "aircraftTravel": {
                // wait for the aircraft to get on station
                private _eventPosition = _eventData select 5;
                private _aircraftID = _eventFriendlyProfiles select 0;
                private _aircraft = [_assets,_aircraftID] call ALiVE_fnc_hashGet;
                private _startPosition = [_aircraft,"startPos"] call ALiVE_fnc_hashGet;
                private _vehicleClass = [_aircraft,"vehicleClass"] call ALiVE_fnc_hashGet;
                private _isVTOL = [_vehicleClass] call ALiVE_fnc_isVTOL;
                private _isOnCarrier = [_aircraft,"isOnCarrier",false] call ALiVE_fnc_hashGet;
                private _launched = [_aircraft,"launched", false] call ALiVE_fnc_hashGet;
                private _count = [_logic, "checkEvent", _event] call MAINCLASS;

                if(_count == 0) exitWith {

                    private _className = getText(configFile >> "CfgVehicles" >> _vehicleClass >> "displayName");
                    private _message = format[localize "STR_ALIVE_ATO_AIRCRAFT_LOST", _HQ, _className, _eventType];
                    // send a message to all side players from HQ
                    private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                    [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

                    // Unlock runway
                    private _airportID = [_aircraft,"airportID",[_startPosition] call ALiVE_fnc_getNearestAirportID] call ALiVE_fnc_hashGet;
                    [_logic, "unlockRunway", _airportID] call MAINCLASS;

                    // set state to event complete
                    if(_playerRequested) then {
                        private _logEvent = ['ATO_RESPONSE', [_requestID,_playerID],"Logistics","REQUEST_LOST"] call ALIVE_fnc_event;
                        [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;
                    };
                    [_event, "state", "eventComplete"] call ALIVE_fnc_hashSet;
                    [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;
                };

                private _profileID = [_aircraft,"profileID"] call ALiVE_fnc_hashGet;
                private _profile = [ALIVE_profileHandler, "getProfile",_profileID] call ALIVE_fnc_profileHandler;
                private _vehicle = [_profile,"vehicle"] call ALiVE_fnc_hashGet;

                // Reset aircraft launch ready state
                [_aircraft,"ready",false] call ALiVE_fnc_hashSet;

                // If aircraft is taking too much time, launch it
                if (time > (_eventTime + ((_eventDuration/2)*60)) ) then {

                    // Check to see if it has taken off, if hasn't launch it
                    if ((getposATL _vehicle) select 2 < 10  || (_isOnCarrier && ((getposASL _vehicle) select 2 < 30))) then {
                        // Launch
                        _vehicle engineOn true;
                        _vehicle setposATL [(getposATL _vehicle) select 0, (getposATL _vehicle) select 1, 600];
                        private _direction = direction _vehicle;
                        private _speed = 200;
                        _vehicle setVelocity [(sin _direction*_speed), (cos _direction*_speed),0.1];
                    };
                };

                // If aircraft is airborne, unlock runway once
                if ( (getposATL _vehicle) select 2 > 50 && (getposASL _vehicle) select 2 > 50 && !_launched) then {
                    // Unlock runway now
                    if (_vehicleClass iskindof "Plane" && ((_isVTOL mod 2) == 0) ) then {
                        private _airportID = [_aircraft,"airportID",[_startPosition] call ALiVE_fnc_getNearestAirportID] call ALiVE_fnc_hashGet;
                        [_logic, "unlockRunway", _airportID] call MAINCLASS;
                    };
                    [_aircraft,"launched", true] call ALiVE_fnc_hashSet;
                };

                if (_debug) then {
                    ["ALIVE ATO %3: aircraft %4 distance %1 (%2)", (_eventPosition distance2D _vehicle),(_eventRange * 1.2), _logic, _profileID] call ALiVE_fnc_dump;
                };

                if ( (_eventPosition distance2D _vehicle) < (_eventRange * 1.2) && (getposATL _vehicle) select 2 > 50 && (getposASL _vehicle) select 2 > 50 ) then {

                    [_event, "state", "aircraftExecuteWait"] call ALIVE_fnc_hashSet;
                    [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;

                    // Aircraft is on station
                    // DEBUG -------------------------------------------------------------------------------------
                    if(_debug) then {
                        ["ALIVE ATO %3 - Requested aircraft (%1 - %2) is on station", _profileID, typeof _vehicle, _logic] call ALIVE_fnc_dump;
                    };
                    // DEBUG -------------------------------------------------------------------------------------

                    // Radio Broadcast
                    private _callsign = groupID (group _vehicle);
                    private _message = format[localize "STR_ALIVE_ATO_ON_STATION", _HQ, _callsign, mapGridPosition _vehicle, _eventType];
                    // send a message to all side players from HQ
                    private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                    [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

                    // respond to player request
                    if(_playerRequested) then {
                        private  _logEvent = ['ATO_RESPONSE', [_requestID,_playerID],"Logistics","REQUEST_ARRIVED"] call ALIVE_fnc_event;
                        [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;
                    };

                    // Reset launched state
                    [_aircraft,"launched", false] call ALiVE_fnc_hashSet;
                };
            };

            case "aircraftExecuteWait": {
                // wait for waypoint to be completed or bingo fuel/weapons or destroyed
                private _eventPosition = _eventData select 5;
                private _aircraftID = _eventFriendlyProfiles select 0;
                private _aircraft = [_assets,_aircraftID] call ALiVE_fnc_hashGet;
                private _vehicleClass = [_aircraft,"vehicleClass"] call ALiVE_fnc_hashGet;

                private _count = [_logic, "checkEvent", _event] call MAINCLASS;
                if(_count == 0) exitWith {

                    //Radio Broadcast
                    private _className = getText(configFile >> "CfgVehicles" >> _vehicleClass >> "displayName");
                    private _message = format[localize "STR_ALIVE_ATO_AIRCRAFT_LOST", _HQ, _className, _eventType];
                    // send a message to all side players from HQ
                    private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                    [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

                    if(_playerRequested) then {
                        private _logEvent = ['ATO_RESPONSE', [_requestID,_playerID],"ATO","REQUEST_LOST"] call ALIVE_fnc_event;
                        [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;
                    };
                    // set state to event complete
                    [_event, "state", "eventComplete"] call ALIVE_fnc_hashSet;
                    [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;
                };


                private _profileID = [_aircraft,"profileID"] call ALiVE_fnc_hashGet;

                private _missionComplete = false;
                private _healthIssue = false;
                private _profile = [ALIVE_profileHandler, "getProfile",_profileID] call ALIVE_fnc_profileHandler;
                private _vehicle = [_profile,"vehicle"] call ALiVE_fnc_hashGet;

                private _radioChoice = "STR_ALIVE_ATO_RETURN";
                if (count waypoints (group _vehicle) > 0) then {
                    // Check waypoint
                    if (time > (_eventTime + (_eventDuration*60)) ) then {
                        _missionComplete = true;
                    };
                } else {
                    _missionComplete = true;
                };

                // Check damage
                private _damage = damage _vehicle;
                if (_damage > 0.5) then {
                    _healthIssue = true;
                    _radioChoice = "STR_ALIVE_ATO_RETURN_DAMAGE";
                };

                // Check fuel
                private _fuel = fuel _vehicle;
                if (_fuel < 0.2) then {
                    _healthIssue = true;
                    _radioChoice = "STR_ALIVE_ATO_RETURN_FUEL";
                };

                // Check Weapons
                // Calculate % of ammo
                private _ammoArray = _vehicle call ALiVE_fnc_vehicleGetAmmo;
                private _avail = 0;
                {
                    _avail = _avail + ((_x select 1)/(_x select 2));
                } foreach _ammoArray;
                private _ammo = _avail / count _ammoArray;
                if (_ammo < 0.1) then {
                    _healthIssue = true;
                    _radioChoice = "STR_ALIVE_ATO_RETURN_AMMO";
                };

                // Check targets
                if (count _eventEnemyProfiles > 0 && _missionComplete && !_healthIssue) then {
                    // Set another waypoint?
                };

                // If waypoint has been completed
                if(_missionComplete || _healthIssue) then {

                    // return home
                    private _eventStateData set [0, _healthIssue];
                    private _eventStateData set [1, _missionComplete];
                    [_event, "stateData", _eventStateData] call ALIVE_fnc_hashSet;

                    // Radio broadcast
                    if !("ItemRadio" in (assignedItems driver _vehicle)) then {
                        driver _vehicle addItem "ItemRadio";
                    };
                    private _callsign = groupID (group _vehicle);
                    private _message = format[localize _radioChoice, _eventType];
                    // send a message to all side players from HQ
                    private _radioBroadcast = [driver _vehicle,_message,"side",_sideObject,true];
                    [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

                    [_event, "state", "aircraftReturn"] call ALIVE_fnc_hashSet;
                    [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;

                };
            };

            case "aircraftReturn": {
                private _aircraftID = _eventFriendlyProfiles select 0;
                private _aircraft = [_assets,_aircraftID] call ALiVE_fnc_hashGet;
                private _vehicleClass = [_aircraft,"vehicleClass"] call ALiVE_fnc_hashGet;
                private _count = [_logic, "checkEvent", _event] call MAINCLASS;
                if(_count == 0) exitWith {

                    // Radio Broadcast
                    private _className = getText(configFile >> "CfgVehicles" >> _vehicleClass >> "displayName");
                    private _message = format[localize "STR_ALIVE_ATO_AIRCRAFT_LOST", _HQ, _className, _eventType];
                    // send a message to all side players from HQ
                    private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                    [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

                    // set state to event complete
                    [_event, "state", "eventComplete"] call ALIVE_fnc_hashSet;
                    [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;
                };

                private _aircraftID = _eventFriendlyProfiles select 0;
                private _aircraft = [_assets,_aircraftID] call ALiVE_fnc_hashGet;
                private _eventPosition = _eventData select 5;
                private _startPosition = [_aircraft,"startPos"] call ALiVE_fnc_hashGet;

                // Set waypoint to land back at starting positions

                // Assign waypoints to the aircraft crew
                private _profileID = [_aircraft,"profileID"] call ALiVE_fnc_hashGet;
                private _profile = [ALIVE_profileHandler, "getProfile",_profileID] call ALIVE_fnc_profileHandler;
                private _vehicle = [_profile,"vehicle"] call ALiVE_fnc_hashGet;

                private _grp = group _vehicle;

                 while {(count (waypoints _grp)) > 0} do
                 {
                    deleteWaypoint ((waypoints _grp) select 0);
                 };

                private _wp = _grp addWaypoint [_startPosition,400];
                _wp setWaypointBehaviour "CARELESS";
                _wp setWaypointCombatMode "BLUE";
                _wp setWaypointStatements ["true","if (alive this) then {vehicle driver this setVariable ['ALIVE_MIL_ATO_RTB',true]; deleteWaypoint [group this, currentWaypoint (group this)];}"];

                // Quiesce group
                _grp enableAttack false;
                {
                    _x disableAI "TARGET";
                    _x disableAI "AUTOTARGET";
                    _x setCombatMode "BLUE";
                } foreach units _grp;

                // dispatch event
                _logEvent = ['ATO_RETURN', [_startPosition,_eventFaction,_side,_eventID],"air tasking orders"] call ALIVE_fnc_event;
                [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;

                // respond to player request
                if(_playerRequested) then {
                    _logEvent = ['ATO_RESPONSE', [_requestID,_playerID],"air tasking orders","REQUEST_RETURN"] call ALIVE_fnc_event;
                    [ALIVE_eventLog, "addEvent",_logEvent] call ALIVE_fnc_eventLog;
                };

                // set state to wait for return of transports
                [_event, "state", "aircraftReturnWait"] call ALIVE_fnc_hashSet;
                [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;
            };

            case "aircraftReturnWait": {

                private _aircraftID = _eventFriendlyProfiles select 0;
                private _aircraft = [_assets,_aircraftID] call ALiVE_fnc_hashGet;
                private _eventPosition = _eventData select 5;
                private _startPosition = [_aircraft,"startPos"] call ALiVE_fnc_hashGet;
                private _vehicleClass = [_aircraft,"vehicleClass"] call ALiVE_fnc_hashGet;
                private _isVTOL = [_vehicleClass] call ALiVE_fnc_isVTOL;
                private _isPlane = _vehicleClass iskindof "Plane" && ((_isVTOL mod 2) == 0);

                private _count = [_logic, "checkEvent", _event] call MAINCLASS;
                if(_count == 0) exitWith {

                    // Radio Broadcast
                    private _className = getText(configFile >> "CfgVehicles" >> _vehicleClass >> "displayName");
                    private _message = format[localize "STR_ALIVE_ATO_AIRCRAFT_LOST", _HQ, _className, _eventType];
                    // send a message to all side players from HQ
                    private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                    [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

                    // Unlock runway
                    if (_isPlane ) then {
                        private _airportID = [_aircraft,"airportID",[_startPosition] call ALiVE_fnc_getNearestAirportID] call ALiVE_fnc_hashGet;
                        [_logic, "unlockRunway", _airportID] call MAINCLASS;
                    };

                    // set state to event complete
                    [_event, "state", "eventComplete"] call ALIVE_fnc_hashSet;
                    [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;
                };

                private _isOnCarrier = [_aircraft,"isOnCarrier"] call ALiVE_fnc_hashGet;
                private _profile = [ALIVE_profileHandler, "getProfile",_aircraftID] call ALIVE_fnc_profileHandler;
                private _vehicle = [_profile,"vehicle"] call ALiVE_fnc_hashGet;
                private _grp = group _vehicle;

                // Check to see if aircraft is in vicinty of starting position
                if(_vehicle getVariable [QGVAR(RTB),false]) then {

                    // Check to see there are any players around
                    private _playersInRange = [_startPosition, 1000] call ALiVE_fnc_anyPlayersInRange;

                    // If players are around then execute landing
                    if (_playersInRange > 0) then {

                        if (_isPlane) then {

                            private _airportID = [_aircraft,"airportID",[_startPosition] call ALiVE_fnc_getNearestAirportID] call ALiVE_fnc_hashGet;
                            private _airportBusy = false;

                            // if plane check to see if runway is busy, wait
                            _airportBusy = [_airports, _airportID] call ALiVE_fnc_hashGet;

                            // DEBUG -------------------------------------------------------------------------------------
                            if(_debug) then {
                                ["ALIVE ATO %3 - Aircraft (%1 - %2) is looking to land at %4 (%5) Plane: %6", _vehicle, typeof _vehicle, _logic, _airportID, _airportBusy, _vehicleClass iskindof "Plane"] call ALIVE_fnc_dump;
                            };
                            // DEBUG -------------------------------------------------------------------------------------

                            if !(_airportBusy) then {

                                // Mark airport as busy for landing
                                [_airports, _airportID, true] call ALiVE_fnc_hashSet;
                                [_logic,"runways",_airports] call MAINCLASS;

                                if (_airportID < 100) then {
                                    _vehicle landAt _airportID;
                                } else {
                                    private _dynamicAirport =  nearestObject [_startPosition, "AirportBase"];
                                    _vehicle landAt _dynamicAirport;
                                };

                                // DEBUG -------------------------------------------------------------------------------------
                                if(_debug) then {
                                    ["ALIVE ATO %3 - Aircraft (%1 - %2) is landing at %4", _vehicle, typeof _vehicle, _logic, _airportID] call ALIVE_fnc_dump;
                                };
                                // DEBUG -------------------------------------------------------------------------------------

                                // add eventhandler for aircraft landing
                                _vehicle addEventHandler ["LandedStopped", {(_this select 0) setVariable [QGVAR(LANDED),true]}];
                                _vehicle addEventHandler ["LandedTouchDown", {(_this select 0) setVariable [QGVAR(LANDEDTOUCHDOWN),time]}];

                                // set state to wait for return of transports
                                [_event, "state", "aircraftLanding"] call ALIVE_fnc_hashSet;
                                [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;
                            };

                        } else {

                            private _helipad = [_aircraft,"helipad"] call ALiVE_fnc_hashGet;

                            // Helicopter or VTOL?
                            if !(_isVTOL mod 2 == 0) then {

                                _vehicle land "LAND";
                                _vehicle landat _helipad;
                                 doGetOut (driver _vehicle);

                            } else {

                                // Tell VTOL to GETOUT at position
                                private _wp = _grp addWaypoint [_startPosition, 400];
                                _wp setWaypointBehaviour "CARELESS";
                                _wp setWaypointCombatMode "BLUE";
                                _wp setWaypointType "TR UNLOAD";
                                doGetOut (driver _vehicle);

                            };

                            // DEBUG -------------------------------------------------------------------------------------
                            if(_debug) then {
                                ["ALIVE ATO %3 - Aircraft (%1 - %2) is landing at %4", _vehicle, typeof _vehicle, _logic, _helipad] call ALIVE_fnc_dump;
                            };
                            // DEBUG -------------------------------------------------------------------------------------

                            // set state to wait for return of transports
                            [_event, "state", "aircraftLanding"] call ALIVE_fnc_hashSet;
                            [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;
                        };

                    } else {

                        _vehicle setVariable [QGVAR(LANDED),true];
                        // set state to wait for return of transports
                        [_event, "state", "aircraftLanding"] call ALIVE_fnc_hashSet;
                        [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;

                    };

                    _vehicle setVariable [QGVAR(LANDING),time];

                };
            };

            case "aircraftLanding": {

                private _aircraftID = _eventFriendlyProfiles select 0;
                private _aircraft = [_assets,_aircraftID] call ALiVE_fnc_hashGet;
                private _isOnCarrier = [_aircraft,"isOnCarrier"] call ALiVE_fnc_hashGet;
                private _startPosition = [_aircraft,"startPos"] call ALiVE_fnc_hashGet;
                private _vehicleClass = [_aircraft,"vehicleClass"] call ALiVE_fnc_hashGet;
                private _isVTOL = [_vehicleClass] call ALiVE_fnc_isVTOL;
                private _isPlane = _vehicleClass iskindof "Plane" && ((_isVTOL mod 2) == 0);
                private _count = [_logic, "checkEvent", _event] call MAINCLASS;

                if(_count == 0) exitWith {

                    // Radio Broadcast
                    private _className = getText(configFile >> "CfgVehicles" >> _vehicleClass >> "displayName");
                    private _message = format[localize "STR_ALIVE_ATO_AIRCRAFT_LOST", _HQ, _className, _eventType];
                    // send a message to all side players from HQ
                    private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                    [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

                    // Unlock runway
                    private _airportID = [_aircraft,"airportID",[_startPosition] call ALiVE_fnc_getNearestAirportID] call ALiVE_fnc_hashGet;
                    [_logic, "unlockRunway", _airportID] call MAINCLASS;

                    // set state to event complete
                    [_event, "state", "eventComplete"] call ALIVE_fnc_hashSet;
                    [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;
                };

                private _profile = [ALIVE_profileHandler, "getProfile",_aircraftID] call ALIVE_fnc_profileHandler;
                private _vehicle = [_profile,"vehicle"] call ALiVE_fnc_hashGet;
                private _grp = group _vehicle;

                private _landingTime = _vehicle getVariable [QGVAR(LANDING), time];

                private _landed = _vehicle getVariable [QGVAR(LANDED),false];
                private _touchDown = _vehicle getVariable [QGVAR(LANDEDTOUCHDOWN),0];

                // Tailhook for carrier landings
                if (_isOnCarrier && _isPlane && !_landed) then {
                    [_vehicle] spawn {
                        private _vehicle = _this select 0;
                        [_vehicle] call BIS_fnc_aircraftTailhook;
                    };
                };

                // manage taxi for planes
                if (_touchDown > 0) then {
                    if ( time > (_touchDown + 180) || (_isOnCarrier && time > (_touchDown + 25)) )  then {
                        _landed = true;
                    };
                };

                if ( _vehicle iskindof "Helicopter" && ( (getposATL _vehicle) select 2 < 2 || (_isOnCarrier && (getposASL _vehicle) select 2 < 25) ) ) then {
                    _landed = true;
                };

                // Check to see if aircraft is in vicinty of starting position
                if(_landed || time > (_landingTime + 300) ) then {

                    // DEBUG -------------------------------------------------------------------------------------
                    if(_debug) then {
                        ["ALIVE ATO %3 - Aircraft (%1 - %2) has landed at time: %4", _vehicle, typeof _vehicle, _logic, _touchDown] call ALIVE_fnc_dump;
                    };
                    // DEBUG -------------------------------------------------------------------------------------

                    // Radio Broadcast
                    private _callsign = groupID _grp;
                    private _message = format[localize "STR_ALIVE_ATO_MISSION_COMPLETE", _HQ, _callsign, _eventType];
                    // send a message to all side players from HQ
                    private _radioBroadcast = [objNull,_message,"side",_sideObject,false,false,false,true,_hqClass];
                    [_side,_radioBroadcast] call ALIVE_fnc_radioBroadcastToSide;

                    _vehicle setVariable [QGVAR(LANDED),false];

                    // Turn off engine
                    _vehicle engineOn false;

                    // Once landed and either on helo position or close to taxi off position then disembark crewzz
                    _vehicle setVelocity [0,0,0];

                    // Set position if plane to taxi position
                    if (_vehicle iskindOf "Plane") then {
                        private _airportID = [_aircraft,"airportID",[_startPosition] call ALiVE_fnc_getNearestAirportID] call ALiVE_fnc_hashGet;
                        private _taxiPositions = [_airportID, "ilsTaxiIn"] call ALiVE_fnc_getAirportTaxiPos;
                        private _taxiPosition = [_taxiPositions select (count _taxiPositions -2), _taxiPositions select (count _taxiPositions -1), 0];
                        if (_isOnCarrier) then {
                            _vehicle setposATL [_startPosition select 0, _startPosition select 1, (_startPosition select 2) + 1];
                        } else {
                            _vehicle setposATL _taxiPosition;
                        };
                    };

                     while {(count (waypoints _grp)) > 0} do
                     {
                        deleteWaypoint ((waypoints _grp) select 0);
                     };

                    if !(_vehicle isKindOf "UAV") then {
                        private _leader = leader _grp;

                        // Crew should be unassigned from aircraft
                        _grp leaveVehicle _vehicle;

                        private _crewpos = (selectRandom ((nearestBuilding _startPosition) buildingPos -1));

                        // tell crew to move to nearest building
                        if (_isOnCarrier) then {
                                private _bridge = (_startPosition nearObjects ["Land_Carrier_01_island_02_F",700]) select 0;
                                _crewPos = ASLtoATL (_bridge modelToWorld [-2.43359,1.98047,0]);
                                {
                                    _x setposATL _crewpos;
                                } foreach units _grp;
                        } else {

                            (group _leader) move _crewPos;
                        };

                        // Set crew profile to move to building.
                        private _crewID = [_aircraft,"crewID",""] call ALiVE_fnc_hashGet;
                        private _crewProfile = [ALIVE_profileHandler, "getProfile",_crewID] call ALIVE_fnc_profileHandler;
                        if !(isNil "_crewProfile") then {
                            private _profileWaypoint = [_crewPos, 2] call ALIVE_fnc_createProfileWaypoint;
                            [_crewProfile, "addWaypoint", _profileWaypoint] call ALIVE_fnc_profileEntity;
                            [_crewProfile,"spawnType",[]] call ALiVE_fnc_profileEntity;
                        };
                    } else {
                        {
                            _vehicle deleteVehicleCrew _x;
                        } foreach (crew _vehicle);
                    };

                    // Turn off engine
                    _vehicle engineOn false;

                    //Move back to original position
                    _vehicle setDir ([_aircraft,"startDir"] call ALiVE_fnc_hashGet);

                    if !(_isOnCarrier) then {
                        _vehicle setposATL _startPosition;
                    };

                    // Airport is no longer busy
                    if (_isPlane ) then {
                        private _airportID = [_aircraft,"airportID",[_startPosition] call ALiVE_fnc_getNearestAirportID] call ALiVE_fnc_hashGet;
                        // Mark airport as not busy
                        [_logic, "unlockRunway", _airportID] call MAINCLASS;
                    };

                    // Reset landing values
                    _vehicle setVariable [QGVAR(LANDED),false];
                    _vehicle setVariable [QGVAR(LANDEDTOUCHDOWN),0];

                    // Refuel, rearm and fix vehicle
                    _vehicle setDamage 0;
                    _vehicle setFuel 1;

                    // turn off prevent despawn
                    [_profile,"spawnType",[]] call ALiVE_fnc_profileVehicle;

                    // remove currentOp from vehicle - add delay so it can't be used for 10 mins?
                    [_aircraft,"currentOp",""] call ALiVE_fnc_hashSet;
                    [_assets,_aircraftID,_aircraft] call ALiVE_fnc_hashSet;

                    // set state to event complete
                    [_event, "state", "eventComplete"] call ALIVE_fnc_hashSet;
                    [_eventQueue, _eventID, _event] call ALIVE_fnc_hashSet;

                };
            };

            case "eventComplete": {

                if (count _eventFriendlyProfiles > 0) then {
                    private _aircraftID = _eventFriendlyProfiles select 0;
                    private _aircraft = [_assets,_aircraftID] call ALiVE_fnc_hashGet;
                    //reset if rerouted
                    [_aircraft,"reroute",false] call ALiVE_fnc_hashSet;
                    [_assets,_aircraftID,_aircraft] call ALiVE_fnc_hashSet;
                };

                // despawn any existing targets
                if (count _eventEnemyProfiles > 0) then {
                    {
                        private _targetProfile = [ALiVE_profileHandler, "getProfile", _x] call ALiVE_fnc_ProfileHandler;
                        if !(isNil "_targetProfile") then {
                            [_targetProfile,"spawnType",[]] call ALiVE_fnc_hashSet;
                        };
                    } foreach _eventEnemyProfiles;
                };

                // send radio broadcast
                _sideObject = [_eventSide] call ALIVE_fnc_sideTextToObject;
                _factionName = getText((_eventFaction call ALiVE_fnc_configGetFactionClass) >> "displayName");

                // TODO RADIO MESSAGE

                //  Update assets?
                _assets = [ALIVE_globalATO,_eventFaction] call ALIVE_fnc_hashGet;

                // remove the event
                [_logic, "removeEvent", _eventID] call MAINCLASS;
            };

            // PLAYER REQUEST ---------------------------------------------------------------------------------------------------------------------------------

            // Would conflict with Combat Support?
        };
    };

    case "checkEvent": {

        private _event = _args;

        private _debug = [_logic, "debug"] call MAINCLASS;

        private _eventID = [_event, "id"] call ALIVE_fnc_hashGet;
        private _eventData = [_event, "data"] call ALIVE_fnc_hashGet;
        private _eventTime = [_event, "time"] call ALIVE_fnc_hashGet;
        private _eventState = [_event, "state"] call ALIVE_fnc_hashGet;
        private _eventStateData = [_event, "stateData"] call ALIVE_fnc_hashGet;
        private _eventFriendlyProfiles = [_event, "friendlyProfiles"] call ALIVE_fnc_hashGet;
        private _eventEnemyProfiles = [_event, "enemyProfiles"] call ALIVE_fnc_hashGet;
        private _playerRequested = [_event, "playerRequested"] call ALIVE_fnc_hashGet;
        private _playerRequestProfiles = [_event, "playerRequestProfiles"] call ALIVE_fnc_hashGet;

        private _eventType = _eventData select 0;
        private _eventSide = _eventData select 1;
        private _eventFaction = _eventData select 2;
        private _eventAirspace = _eventData select 3;
        private _eventATO = _eventData select 4;

        private _eventTargets = _eventATO select 7;

        private _totalCount = 0;

        _eventFriendlyProfiles = [_logic, "removeUnregisteredProfiles", _eventFriendlyProfiles] call MAINCLASS;
        [_event, "friendlyProfiles", _eventFriendlyProfiles] call ALIVE_fnc_hashSet;

        _totalCount = count _eventFriendlyProfiles;

        if (_totalCount != 0) then {

            _eventEnemyProfiles = [_logic, "removeUnregisteredProfiles", _eventEnemyProfiles] call MAINCLASS;
            [_event, "enemyProfiles", _eventEnemyProfiles] call ALIVE_fnc_hashSet;

            _totalCount = _totalCount + count _eventEnemyProfiles;
        };

        _result = _totalCount;
    };

    case "removeUnregisteredProfiles": {

        private ["_profiles","_profile"];

        _profiles = _args;

        {
            _profile = [ALIVE_profileHandler, "getProfile", _x] call ALIVE_fnc_profileHandler;
            if(isNil "_profile") then {
                _profiles set [_forEachIndex,"DELETE"];
                // Remove the asset
                private _assets = [_logic,"assets"] call MAINCLASS;
                if ([_assets,_x] call CBA_fnc_hashHasKey) then {

                    // remove it from airspace assets first
                    private _airspace = [[_assets,_x] call ALiVE_fnc_hashGet,"airspace"] call ALiVE_fnc_hashGet;
                    private _as = [[_logic,"airspaceAssets"] call MAINCLASS, _airspace] call ALiVE_fnc_hashGet;
                    _as = _as - [_x];
                    [[_logic,"airspaceAssets"] call MAINCLASS, _airspace, _as] call ALiVE_fnc_hashSet;

                    // remove it from assets
                    [_assets,_x] call CBA_fnc_hashRem;
                    [_logic,"assets",_assets] call MAINCLASS;
                };
            };

        } forEach _profiles;

        _profiles = _profiles - ["DELETE"];

        _result = _profiles;
    };

    case "removeEvent": {
        private["_debug","_eventID","_eventQueue"];

        // remove the event from the queue

        _eventID = _args;
        _eventQueue = [_logic, "eventQueue"] call MAINCLASS;

        [_eventQueue,_eventID] call ALIVE_fnc_hashRem;

        [_logic, "eventQueue", _eventQueue] call MAINCLASS;
    };
};

TRACE_1("ATO - output",_result);
_result;
