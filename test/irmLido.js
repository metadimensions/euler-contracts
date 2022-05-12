const et = require('./lib/eTestLib');

const A_DAY = 86400
const START_BLOCK = 14707000
const LIDO_SPY_AT_14707000 = et.BN('1270366590784250048')
const LIDO_SPY_CUSTOM_1 = et.BN('1000000000000000000')
const LIDO_SPY_CUSTOM_2 = et.BN('-1000000000000000000')

const LIDO_ORACLE_ADDRESS = '0x442af784A788A5bd6F42A01Ebe9F287a871243fb'
const POST_COMPLETED_TOTAL_POOLED_ETHER_POSITION = '0xaa8433b13d2b111d4f84f6f374bc7acbe20794944308876aa250fa9a73dc7f53'
const PRE_COMPLETED_TOTAL_POOLED_ETHER_POSITION = '0x1043177539af09a67d747435df3ff1155a64cd93a347daaac9132a591442d43e'
const TIME_ELAPSED_POSITION = '0x8fe323f4ecd3bf0497252a90142003855cc5125cee76a5b5ba5d508c7ec28c3a'

// storage slot hashes are taken from the github repo
// https://github.com/lidofinance/lido-dao/blob/master/contracts/0.4.24/oracle/LidoOracle.sol

function setLidoOracleStorage(ctx, post, pre, elapsed) {
    ctx.setStorageAt(
        LIDO_ORACLE_ADDRESS, 
        POST_COMPLETED_TOTAL_POOLED_ETHER_POSITION, 
        '0x' + et.BN(post).toHexString().slice(2).padStart(64, '0')
    )
    ctx.setStorageAt(
        LIDO_ORACLE_ADDRESS, 
        PRE_COMPLETED_TOTAL_POOLED_ETHER_POSITION, 
        '0x' + et.BN(pre).toHexString().slice(2).padStart(64, '0')
    )
    ctx.setStorageAt(
        LIDO_ORACLE_ADDRESS, 
        TIME_ELAPSED_POSITION, 
        '0x' + et.BN(elapsed).toHexString().slice(2).padStart(64, '0')
    )
}

function apy(v) {
    let apr = Math.log(v + 1);

    let spy = ethers.BigNumber.from(Math.floor(apr * 1e6))
              .mul(ethers.BigNumber.from(10).pow(27 - 6))
              .div(et.SecondsPerYear);

    return spy;
}

function apyInterpolate(apy, frac) {
    return Math.exp(Math.log(1 + apy) * frac) - 1;
}

et.testSet({
    desc: "irm lido",
    fixture: 'mainnet-fork',
    forkAtBlock: START_BLOCK,

    // the IRM LIDO model is meant to be used to offset the STETH interest rate.
    // for this test however USDT instead for STETH is used as underlying. for the purpose 
    // of this test the balace of the underlying token needs to be modified directly in 
    // the storage (we need to mint tokens for ourselves so we can deposit and borrow them).
    // as STETH is a rebase token it's not easy to override appropriate storage slots, hence USDT is used
    preActions: ctx => [
        { action: 'setAssetConfig', tok: 'USDT', config: { borrowFactor: 1}, },
        { action: 'setReserveFee', underlying: 'USDT', fee: 0, },
        { action: 'setIRM', underlying: 'USDT', irm: 'IRM_LIDO', },
        { action: 'setAssetConfig', tok: 'USDC', config: { collateralFactor: 1}, },

        { action: 'setTokenBalanceInStorage', token: 'USDT', for: ctx.wallet.address, amount: 110_000 },
        { send: 'tokens.USDT.approve', args: [ctx.contracts.euler.address, et.MaxUint256], },
        { send: 'eTokens.eUSDT.deposit', args: [0, et.units(100_000, 6)], },
        { send: 'markets.enterMarket', args: [0, ctx.contracts.tokens.USDC.address], },

        { action: 'setTokenBalanceInStorage', token: 'USDC', for: ctx.wallet.address, amount: 100_000 },
        { send: 'tokens.USDC.approve', args: [ctx.contracts.euler.address, et.MaxUint256], },
        { send: 'eTokens.eUSDC.deposit', args: [0, et.MaxUint256], },
        { send: 'markets.enterMarket', args: [0, ctx.contracts.tokens.USDC.address], },
    ],
})



.test({
    desc: "APRs",
    actions: ctx => [
        
        // Base=Lido APY, Kink(50%)=10% APY  Max=300% APY

        // 0% utilisation
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [apy(0), 1e-5], },

        // the smallest possible non-zero utilisation
        { send: 'dTokens.dUSDT.borrow', args: [0, 1], },
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [LIDO_SPY_AT_14707000, 1e-5], },

        // 25% utilisation
        { send: 'dTokens.dUSDT.borrow', args: [0, et.units(25_000, 6).sub(1)], },
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [LIDO_SPY_AT_14707000.add(apy(apyInterpolate(.1, .5))), 1e-5], },

        // repay, withdraw and deposit again before time jump not to have utilisation ratio screwed due to interest accrual
        { send: 'dTokens.dUSDT.repay', args: [0, et.MaxUint256], },
        { send: 'eTokens.eUSDT.withdraw', args: [0, et.MaxUint256], },
        { send: 'eTokens.eUSDT.deposit', args: [0, et.units(100_000, 6)], },

        { action: 'cb', cb: async () => {
            // SPY = 1e27 * (post - pre) / (pre * elapsed)
            // the following will correspond to SPY = 1e18
            setLidoOracleStorage(ctx, '1000500000000000000000000', '1000000000000000000000000', '500000')

            // jump a bit less as it's not accurate
            ctx.jumpTime(A_DAY - 50)
        }},

        // 50% utilisation, new APY shouldn't be read and stored yet
        { send: 'dTokens.dUSDT.borrow', args: [0, et.units(50_000, 6)], },
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [LIDO_SPY_AT_14707000.add(apy(.1)), 1e-5], },

        // repay, withdraw and deposit again before time jump not to have utilisation ratio screwed due to interest accrual
        { send: 'dTokens.dUSDT.repay', args: [0, et.MaxUint256], },
        { send: 'eTokens.eUSDT.withdraw', args: [0, et.MaxUint256], },
        { send: 'eTokens.eUSDT.deposit', args: [0, et.units(100_000, 6)], },

        // jump to pass A_DAY, a bit more as it's not accurate
        { action: 'jumpTime', time: 100, },

        // new APY should be read now. A_DAY elapsed, utilisation did not change (still 50%)
        { send: 'dTokens.dUSDT.borrow', args: [0, et.units(50_000, 6)], },
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [LIDO_SPY_CUSTOM_1.add(apy(.1)), 1e-5], },

        // 75% utilisation
        { send: 'dTokens.dUSDT.borrow', args: [0, et.units(25_000, 6)], },
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [LIDO_SPY_CUSTOM_1.add(apy(3).sub(apy(.1)).div(2).add(apy(.1))), 1e-5], },

        // 100% utilisation
        { send: 'dTokens.dUSDT.borrow', args: [0, et.units(25_000, 6)], },
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [LIDO_SPY_CUSTOM_1.add(apy(3)), 1e-4], },

        // back to 25% utilisation
        { send: 'dTokens.dUSDT.repay', args: [0, et.units(75_000, 6)], },
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [LIDO_SPY_CUSTOM_1.add(apy(apyInterpolate(.1, .5))), 1e-5], },

        // repay, withdraw and deposit again before time jump not to have utilisation ratio screwed due to interest accrual
        { send: 'dTokens.dUSDT.repay', args: [0, et.MaxUint256], },
        { send: 'eTokens.eUSDT.withdraw', args: [0, et.MaxUint256], },
        { send: 'eTokens.eUSDT.deposit', args: [0, et.units(100_000, 6)], },

        { action: 'cb', cb: async () => {
            // SPY = 1e27 * (post - pre) / (pre * elapsed)
            // the following will correspond to SPY = -1e18 
            setLidoOracleStorage(ctx, '999500000000000000000000', '1000000000000000000000000', '500000')

            // jump a bit more as it's not accurate
            ctx.jumpTime(A_DAY + 50)
        }},

        // 0% utilisation
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [apy(0), 1e-5], },

        // the smallest possible non-zero utilisation
        { send: 'dTokens.dUSDT.borrow', args: [0, 1], },
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [LIDO_SPY_CUSTOM_2, 1e-5], },

        // 25% utilisation
        { send: 'dTokens.dUSDT.borrow', args: [0, et.units(25_000, 6).sub(1)], },
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [LIDO_SPY_CUSTOM_2.add(apy(apyInterpolate(.1, .5))), 1e-5], },

        // 50% utilisation
        { send: 'dTokens.dUSDT.borrow', args: [0, et.units(25_000, 6)], },
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [LIDO_SPY_CUSTOM_2.add(apy(.1)), 1e-5], },

        // 75% utilisation
        { send: 'dTokens.dUSDT.borrow', args: [0, et.units(25_000, 6)], },
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [LIDO_SPY_CUSTOM_2.add(apy(3).sub(apy(.1)).div(2).add(apy(.1))), 1e-5], },

        // 100% utilisation
        { send: 'dTokens.dUSDT.borrow', args: [0, et.units(25_000, 6)], },
        { call: 'markets.interestRate', args: [ctx.contracts.tokens.USDT.address], equals: [LIDO_SPY_CUSTOM_2.add(apy(3)), 1e-4], },
    ],
})

.run();
