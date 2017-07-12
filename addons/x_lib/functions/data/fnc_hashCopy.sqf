#include <\x\alive\addons\x_lib\script_component.hpp>
SCRIPT(hashCopy);

/* ----------------------------------------------------------------------------
Function: ALiVE_fnc_hashCopy

Description:
Copies a hash.

Parameters:
Array - hash
Array - whitelist keys
Array - blacklist keys

Returns:
Array - The new hash

Examples:
(begin example)
_result = [_hash, ["apples","oranges"], ["grapes"]] call ALiVE_fnc_hashCopy;
(end)

See Also:

Author:
ARJay
---------------------------------------------------------------------------- */

private ["_hash","_key","_value","_copy","_hashCopy","_arrayCopy"];

params ["_target", ["_whitelist", []], ["_blacklist", []]];

_hash = [] call ALIVE_fnc_hashCreate;

{
    _key = _x;
    _value = [_target,_key] call ALIVE_fnc_hashGet;
    _copy = true;

    if(count _whitelist > 0) then {
        _copy = false;
        if(_key in _whitelist) then {
            _copy = true;
        };
    };

    if(count _blacklist > 0) then {
        _copy = false;
        if!(_key in _blacklist) then {
            _copy = true;
        };
    };

    if(_copy) then {
        if(_value isEqualType []) then {
            if([_value] call ALIVE_fnc_isHash) then {
                _hashCopy = [_value, _whitelist, _blacklist] call ALiVE_fnc_hashCopy;
                [_hash, _key, _hashCopy] call ALIVE_fnc_hashSet;
            } else {
                _arrayCopy = [];
                _arrayCopy = + _value;
                [_hash, _key, _arrayCopy] call ALIVE_fnc_hashSet;
            };
        }else{
            [_hash, _key, _value] call ALIVE_fnc_hashSet;
        }
    };
    false
} count (_target select 1);

_hash
