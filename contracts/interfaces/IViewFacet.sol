// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { Position } from "../AppStorage.sol";

interface IViewFacet {

    function getMaxLiquidatorLeverageToAcquirePosition() external view returns (uint256);

    function getTotalOBTradedSize(address indexToken) external view returns (uint256);

    function isValidIndexToken(address _indexToken) external view returns (bool);

    function compartments(address _indexToken) external view returns (uint256, uint256, bool);

    function borrowedAmountFromPool(address _indexToken) external view returns (uint256, uint256, uint256);

    function getTotalIndexTokens() external view returns (uint256);

    function allIndexTokens(uint256 ind) external view returns (address);

    function getUsdBalance() external view returns (uint256);

    function getClaimableAmount(address _address) external view returns (uint256);

    function isSequencerWhitelisted(address _sequencer) external view returns (bool);

    function isProtocolLiquidatorAddress(address _address) external view returns (bool);

    function totalBorrowedUSD() external view returns (uint256);

    function getPositionKey(address _account, address _previousAccount, address _indexToken, bool _isLong)
        external
        pure
        returns (bytes32);

    function getPosition(bytes32 key) external view returns (Position memory);

    function getPositionSize(address _account, address _indexToken, bool _isLong) external view returns (uint256);

    function getOptimalUtilization(address _indexToken) external view returns (uint256);

}
