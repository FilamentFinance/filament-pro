// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { Position } from "../AppStorage.sol";

interface IVaultFacet {

    // Functions
    function addIndexToken(address _address) external payable;

    function addNewAsset(address[] calldata _address, uint256[] calldata _percentage) external payable;

    function updateEpochDuration(uint256 time) external payable;

    function compartmentalize() external;

    // function isADLNeeded(address _address, uint256 _price) external view returns (bool);

    function addLiquidity(uint256 _amount) external;

    function updateCollateralFromLiquidation(Position memory, bytes32 _key) external;

    function updatePositionForLiquidator(bytes32 _escrowKey, bytes32 _newKey, Position memory _newPosition) external;

    function getBorrowRate(address _indexToken) external view returns (uint256, uint256);

}
