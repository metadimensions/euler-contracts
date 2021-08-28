pragma solidity ^0.8.0;

import "./BasePOC.sol";
import "./RiskManager.sol";

contract EToken is BasePOC {
    constructor() BaseModule(MODULEID__ETOKEN) {}

    address public constant proxyAddr = address(1);
    // TODO override me
    function CALLER() private view returns (address, AssetStorage storage, address, address) {
        (address msgSender,) = unpackTrailingParams();
        AssetStorage storage assetStorage = eTokenLookup[proxyAddr];
        address underlying = assetStorage.underlying;
        require(underlying != address(0), "e/unrecognized-etoken-caller");
        return (underlying, assetStorage, proxyAddr, msgSender);
    }

    // function mint(uint subAccountId, uint amount) external nonReentrant {
    //     (address underlying, AssetStorage storage assetStorage, address proxyAddr, address msgSender) = CALLER();
    //     address account = getSubAccount(msgSender, subAccountId);
    //     // updateAverageLiquidity(account);

    //     AssetCache memory assetCache = loadAssetCache(underlying, assetStorage);

    //     amount = decodeExternalAmount(assetCache, amount);

    //     // // Mint ETokens

    //     increaseBalance(assetStorage, assetCache, proxyAddr, account, balanceFromUnderlyingAmount(assetCache, amount));

    //     // // Mint DTokens

    //     increaseBorrow(assetStorage, assetCache, assetStorage.dTokenAddress, account, amount);

    //     checkLiquidity(account);
    //     logAssetStatus(assetCache);
    // }

    // function balanceOf(address account) external view returns (uint) {
    //     (, AssetStorage storage assetStorage,,) = CALLER();

    //     return assetStorage.users[account].balance;
    // }

    function testInternalModule() external returns (address) {
        bytes memory res = callInternalModule(MODULEID__RISK_MANAGER, abi.encodeWithSelector(RiskManager.rTestLink.selector));
        return abi.decode(res, (address));
    }

    function getUnderlying() public view returns (address) {
        return eTokenLookup[proxyAddr].underlying;
    }
}