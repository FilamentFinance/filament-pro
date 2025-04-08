// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

interface IMakerVault {

    function initialize(
        address _usdc,
        address _depositC,
        address _vaultOwner,
        uint256 minUSDCvalue,
        uint256 feePercantage,
        string memory _name,
        string memory _symbol
    ) external;

    function addLiquidityToVault(uint256 _amount) external;

    function removeLiquidityFromVault(uint256 _lpTokenAmount) external;

}
