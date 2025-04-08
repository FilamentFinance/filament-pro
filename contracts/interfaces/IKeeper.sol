// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import "./IRouter.sol";

interface IKeeper {

    // @dev All the fees are in percentages
    // with 2 decimals i.e. in basis points
    // This is the way fees will be distributed/socialised
    struct TradeFeeDistribution {
        uint256 referralPortion; // 0
        uint256 lp; // 45%
        uint256 protocolTreasury; // 45%
        uint256 filamentTokenStakers; // 0
        uint256 insurance; // 10%
    }

    // @dev All the fees are in percentages
    // with 2 decimals i.e. in basis points
    // This is the way fees will be distributed/socialised
    struct BorrowingFeeDistribution {
        uint256 lp; // 80%
        uint256 protocolTreasury; // 20%
    }

    event ProtocolTreasuryUpdated(address newProtocolTreasury);
    event InsuranceUpdated(address newInsurance);
    event ReferralContractUpdated(address indexed newReferralContract);
    event VaultContractUpdated(address newVaultContract);
    event LiquidationFeesUpdated(uint256 newLiquidationFees);
    event TradingFeeDistributionUpdated(
        uint256 referralPortion,
        uint256 lp,
        uint256 protocolTreasury,
        uint256 filamentTokenStakers,
        uint256 insurancePortion
    );
    event BorrowingFeeDistributionUpdated(uint256 lp, uint256 protocolTreasury);

    function distributeTradeFees(uint256 feesInUSD, address _indexToken, address _account) external;
    function distributeBorrowingFees(address _indexToken, uint256 feesInUSD) external;
    function getTotalFeesCollectedFromTrader(address _trader) external view returns (uint256);
    function updateLiquidationFeesCollected(uint256 feesInUSD) external;
    function getProtocolTreasury() external view returns (address);

}
