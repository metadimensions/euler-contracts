// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "../../BaseIRM.sol";

contract IRMReactiveV1 is BaseIRM {
    constructor() BaseIRM(MODULEID__IRM_REACTIVE_V1) {}

    // Number of seconds in year
    int internal constant T = int(365.2425 * 86400); // Gregorian calendar

    // Parameterised in APR/APY terms 
    int internal constant kD = int(1e27) * int(1) / int(10); // 0.1
    int internal constant kA = int(1e27) * int(10) / int(1); // max 10% growth per day

    int internal constant rMax = int(1e27) * int(10); // 1000% APR
    int internal constant uTarget = int(1e27) * int(7) / int(10); // 0.7

    struct UnderlyingStorage {
        uint32 prevUtilisation;
        int96 prevInterestRate;
        uint40 prevTimestamp;
    }

    struct ModelStorage {
        mapping(address => UnderlyingStorage) underlyingLookup;
    }

    function computeInterestRate(address underlying, uint32 utilisation) external override returns (int96) {
        // Load previous values from storage

        UnderlyingStorage storage underlyingStorage;
        uint32 prevUtilisation;
        int96 prevInterestRate;
        uint deltaT;

        {
            ModelStorage storage modelStorage;
            {
                bytes32 storagePosition = keccak256("euler.irm.smoothed");
                assembly { modelStorage.slot := storagePosition }
            }

            underlyingStorage = modelStorage.underlyingLookup[underlying];

            prevUtilisation = underlyingStorage.prevUtilisation;
            prevInterestRate = underlyingStorage.prevInterestRate;
            uint40 prevTimestamp = underlyingStorage.prevTimestamp;

            deltaT = block.timestamp - prevTimestamp;
        }


        // Compute new interest rate

        int u = int(uint(utilisation)) * int(1e27) / int(uint(type(uint32).max));
        int uLast = int(uint(prevUtilisation)) * int(1e27) / int(uint(type(uint32).max));
        int uDelta = u - uLast;        
        int rLast = int(prevInterestRate) * T; // TODO: convert SPY to APY, gives loss of precision here, meaning prevInterestRate not exactly equal to rTarget

        // The relative distance between utilisation and its target and the interest rate and its target
        int uDist = 0;
        int rDist = int(1e27);
        if (u < uTarget) {
            uDist = -(uTarget - u) * int(1e27) / uTarget;            
            rDist = rLast * int(1e27) / rMax; // slows control if interest rate is already relatively small
        } else {
            uDist = (u - uTarget) * int(1e27) / (int(1e27) - uTarget);
            rDist = (rMax - rLast) * int(1e27) / rMax; // slows control if interest rate is already relatively large
        }

        // Sets a maximum increase even when gap between transactions is large
        if(deltaT > uint(24 * 60 * 60)) {
            deltaT = uint(24 * 60 * 60);
        }

        int base = uDelta * kD / int(1e27);
        int control = uDist * rDist / int(1e27) * int(deltaT) / int(24 * 60 * 60) * kA / int(1e27);

        // New interest rate depends on three terms - default with param kD, amplification with param kA, and control with param kC      
        int r = rLast + base + control;
            
        // Final sanity check
        if (r > rMax) {
            r = rMax;
        } else if(r < 0) {
            r = 0;
        }

        // Only calculate per-second basis at the end
        int96 newInterestRate = int96(r  / T);


        // Save updated values and return new IR

        underlyingStorage.prevUtilisation = utilisation;
        underlyingStorage.prevInterestRate = newInterestRate;
        underlyingStorage.prevTimestamp = uint40(block.timestamp);

        return newInterestRate;
    }
}