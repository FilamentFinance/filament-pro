// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

interface IDeposit {

    struct WithdrawRequest {
        uint256 amount;
        uint256 cooldownTime;
        bool isSuspicious;
    }

    function balances(address _address) external returns (uint256 balance);
    function deposit(uint256 _amount) external;
    function requestWithdraw(uint256 _amount) external;
    function claimWithdraw() external;
    function lockForAnOrder(address _account, uint256 _amount) external;
    function transferIn(address _trader, uint256 amount) external;
    function transferOutLiquidity(address _trader, uint256 amount) external;

}
