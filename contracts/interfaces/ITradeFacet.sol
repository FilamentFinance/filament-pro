// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { Position, TraderType, TransactionType } from "./ICommon.sol";

interface ITradeFacet {

    enum MatchType {
        MatchOrders,
        MatchWithPool
    }

    struct PositionParams {
        uint256 collateralDelta;
        uint256 indexDelta;
        uint256 price;
        uint256 orderId;
        uint256 tradeFee;
        uint256 borrowFee;
        int256 fundingFee;
        address account;
        address indexToken;
        MatchType matchType;
        TraderType traderType;
        bool isLong;
    }

    function increasePosition(PositionParams memory _increasePosition) external returns (Position memory);

    function decreasePosition(PositionParams memory decreasePosition) external returns (uint256);

    function addLPFees(uint256 feesUSD, address _indexToken) external;

    function getNextAveragePrice(
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _nextPrice,
        uint256 _indexDelta
    ) external pure returns (uint256 nextAvgPrice);

}
