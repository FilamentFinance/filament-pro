// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

/**
 * \
 * Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
 * EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
 *
 * Implementation of a diamond.
 * /*****************************************************************************
 */
import { IDiamondCut } from "../interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "../interfaces/IDiamondLoupe.sol";
import { IERC165 } from "../interfaces/IERC165.sol";
import { IERC173 } from "../interfaces/IERC173.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {AppStorage } from "../AppStorage.sol";

// It is expected that this contract is customized if you want to deploy your diamond
// with data from a deployment script. Use the init function to initialize state variables
// of your diamond. Add parameters to the init function if you need to.

contract DiamondInit is Initializable, ReentrancyGuardUpgradeable, PausableUpgradeable {

    AppStorage internal s;

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    // You can add parameters to this function in order to pass in
    // data to set your own state variables
    function init()
        external
        onlyOwner
        initializer
    {
        // adding ERC165 data
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;

        // add your own state variables
        // EIP-2535 specifies that the `diamondCut` function takes two optional
        // arguments: address _init and bytes calldata _calldata
        // These arguments are used to execute an arbitrary function using delegatecall
        // in order to set state variables in the diamond during deployment or an upgrade
        // More info here: https://eips.ethereum.org/EIPS/eip-2535#diamond-interface

        __Pausable_init();
        __ReentrancyGuard_init();

        s.compartmentalizationTime = 1 hours;
        s.epochDuration = 72;
        s.dustSize = 1e14; // $0.0001 
        s.maxLiquidatorLeverageToAcquirePosition = 20;
        s.maxLeverage = 70 * 1e18; //70X
    }

    /** 
    * @notice Pauses the contract, preventing certain actions from being executed. // #Zokyo-58
    * @dev Can only be called by the contract owner.
    */
    function pause() external payable onlyOwner {
        _pause();
    }

    /**
    * @notice Unpauses the contract, allowing paused actions to resume.
    * @dev Can only be called by the contract owner.
    */
    function unpause() external payable onlyOwner {
        _unpause();
    }

}
