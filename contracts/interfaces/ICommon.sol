// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

uint256 constant BASIS_POINTS_DIVISOR = 10_000; // 1% = 100
uint256 constant INTEREST_RATE_DECIMALS = 1_000_000;

enum TransactionType {
    MatchOrders,
    MatchWithPool
}

enum TraderType {
    Maker,
    Taker,
    None
}
// @audit - N1 - Removed - fix
// enum Direction {
//     LongToShort,
//     ShortToLong
// }

struct Position {
    uint256 size; // size in usdc
    uint256 collateral;
    uint256 averagePrice;
    uint256 reserveAmount;
    uint256 viaOrder;
    uint256 lastIncreasedTime;
    uint256 creationTime;
    uint256 tradingFee;
    int256 realisedPnl;
    address indexToken;
    bool isLong;
}

struct BorrowedAmount {
    uint256 total;
    uint256 long;
    uint256 short;
}

struct Stake {
    uint256 stakedAmount;
    uint256 unstakedRequested;
    uint256 unstakeClaimed;
}

struct UnstakeRequest {
    uint256 amount;
    uint256 requestDay;
}

struct Compartment {
    uint256 balance;
    uint256 assignedPercentage;
    bool isValid;
}

// @audit - N1 - Removed - fix
struct LiquidablePositionDetails {
    uint256 collateralForLiquidation;
    // uint256 collateralizationValue;
    uint256 positionTransferredTimestamp;
    bool isBadDebtPosition;
}

struct InterestRateParameters {
    address indexToken; // The asset for which these parameters are set
    uint256 Bs; // The base Rate for the first equation (decimals: 10^6), // 1% means 10000
    uint256 S1; // The slope for the first equation (decimals: 10^2), // 30 means 3000
    uint256 S2; // The slope for the second equation (decimals: 10^2) // 75 means 7500
    uint256 Uo; // The optimal utilization (4 decimals, usually 8000; 0 < Uo < 10000), // 80% to 100%
}
