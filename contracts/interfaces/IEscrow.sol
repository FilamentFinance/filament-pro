// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { Position } from "../AppStorage.sol";

interface IEscrow {

    function updateAllLiquidablePositions(bytes32 key, uint256 collateral, Position memory) external;

}
