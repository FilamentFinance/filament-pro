// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { TraderType, TransactionType } from "./ICommon.sol";

interface IRouter {

    struct Order {
        uint256 collateral;
        uint256 amount;
        uint256 priceX18;
        uint256 tradeFee;
        uint256 borrowFee;
        int256 fundingFee;
        address sender;
        address indexToken;
        TraderType traderType;
        bool reduceOnly;
        bool isLong;
    }

    struct MatchOrders {
        uint256 matchId;
        Order taker;
        Order maker;
    }

    struct MatchWithPool {
        uint256 matchId;
        Order order;
    }

}
