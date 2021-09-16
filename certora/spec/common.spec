
methods {
    // asset storage getters ///////////////////////////////////////////////////////
    et_lastInterestAccumulatorUpdate (address eToken)          returns uint40  envfree
    et_underlyingDecimals            (address eToken)          returns uint8   envfree
    et_interestRateModel             (address eToken)          returns uint32  envfree
    et_interestRate                  (address eToken)          returns int96   envfree
    et_reserveFee                    (address eToken)          returns uint32  envfree
    et_pricingType                   (address eToken)          returns uint16  envfree
    et_pricingParameters             (address eToken)          returns uint32  envfree
    et_underlying                    (address eToken)          returns address envfree
    et_reserveBalance                (address eToken)          returns uint96  envfree
    et_dTokenAddress                 (address eToken)          returns address envfree
    et_totalBalances                 (address eToken)          returns uint112 envfree
    et_totalBorrows                  (address eToken)          returns uint144 envfree
    et_interestAccumulator           (address eToken)          returns uint    envfree
    et_user_balance             (address eToken, address user) returns uint112 envfree
    et_user_owed                (address eToken, address user) returns uint144 envfree
    et_user_interestAccumulator (address eToken, address user) returns uint    envfree
    et_eTokenAllowance (address eToken, address a, address b)  returns uint    envfree
    et_dTokenAllowance (address eToken, address a, address b)  returns uint    envfree

    computeNewAverageLiquidity(address,uint) => NONDET
    computeUtilisation(uint,uint)            => NONDET
    _computeExchangeRate(uint,uint,uint)     => NONDET


    // Storage.sol state variable getters
    reentrancyLock() returns (uint) => DISPATCHER(true)
    upgradeAdmin() returns (address) => DISPATCHER(true)
    governorAdmin() returns (address) => DISPATCHER(true)

    moduleLookup(uint) returns (address) => DISPATCHER(true)
    proxyLookup(uint) returns (address) => DISPATCHER(true)

    trustedSenders(address) returns (uint32, address) => DISPATCHER(true) // returns TrustedSenderInfo

    accountLookup(address) returns (bool, uint40, uint32, address, uint) => DISPATCHER(true) // returns AccountStorage
    marketsEntered(address) returns (address[]) => DISPATCHER(true)

    underlyingLookup(address) returns (address, bool, uint32, uint32, uint24) => DISPATCHER(true) // returns AssetConfig
    dTokenLookup(address) returns (address) => DISPATCHER(true)
    pTokenLookup(address) returns (address) => DISPATCHER(true)
}
}


rule sanity(method f) { 
    env e; calldataarg args;

    f(e,args);

    assert false,
        "this should fail";
}

