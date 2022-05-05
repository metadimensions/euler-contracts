// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../../BaseIRM.sol";

interface ILidoOracle {
    function getLastCompletedReportDelta() external view returns (uint postTotalPooledEther, uint preTotalPooledEther, uint timeElapsed);
}

contract IRMLido is BaseIRM {
    uint constant A_DAY = 24 * 60 * 60;
    address public immutable lidoOracle;
    uint public immutable slope1;
    uint public immutable slope2;
    uint public immutable kink;

    struct IRMLidoStorage {
        int96 baseRate;
        uint64 lastCalled;
    }

    constructor(bytes32 moduleGitCommit_) BaseIRM(MODULEID__IRM_LIDO, moduleGitCommit_) {
        lidoOracle = 0x442af784A788A5bd6F42A01Ebe9F287a871243fb;

        // Base=Lido APY, Kink(50%)=10% APY  Max=300% APY
        slope1 = 1406417851;
        slope2 = 19050045013;
        kink = 2147483648;
    }

    function computeInterestRateImpl(address, uint32 utilisation) internal override returns (int96) {
        int ir = 0;
        if (utilisation > 0) {
            IRMLidoStorage storage irmLido;
            {
                bytes32 storagePosition = keccak256("euler.irm.lido");
                assembly { irmLido.slot := storagePosition }
            }

            if (block.timestamp - irmLido.lastCalled > A_DAY) {
                (bool success, bytes memory data) = lidoOracle.staticcall(abi.encodeWithSelector(ILidoOracle.getLastCompletedReportDelta.selector));
            
                if (success) {
                    (uint postTotalPooledEther, uint preTotalPooledEther, uint timeElapsed) = abi.decode(data, (uint, uint, uint));
                    int baseRate = 1e27 * (int(postTotalPooledEther) - int(preTotalPooledEther)) / int(preTotalPooledEther * timeElapsed);
                    
                    // reflect Lido's 10% reward fee
                    //if (baseRate > 0) {
                    //    baseRate = baseRate * 9 / 10;
                    //}

                    irmLido.baseRate = int96(baseRate);
                    irmLido.lastCalled = uint64(block.timestamp);
                }
            }
            ir = irmLido.baseRate;
        }
        
        if (utilisation <= kink) {
            ir += int(utilisation * slope1);
        } else {
            ir += int(kink * slope1);
            ir += int(slope2 * (utilisation - kink));
        }

        return int96(ir);
    }
}
