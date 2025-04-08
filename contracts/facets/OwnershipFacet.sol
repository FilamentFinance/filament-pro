// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.27;

import { IERC173 } from "../interfaces/IERC173.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";

/// @title OwnershipFacet
/// @notice Handles ownership functionality for the diamond contract
/// @dev Implements IERC173 interface for ownership management
contract OwnershipFacet is IERC173 {

    /// @notice Transfers ownership of the contract to a new address
    /// @dev Can only be called by the current owner
    /// @param _newOwner Address of the new owner
    function transferOwnership(address _newOwner) external override {
        // @audit - PVE002 - fix - Don't include in the report
        address _previousContractOwner = LibDiamond.contractOwner();
        LibDiamond.enforceIsContractOwner();
        LibDiamond.setContractOwner(_newOwner);
        emit OwnershipTransferred(_previousContractOwner, _newOwner);
    }

    /// @notice Gets the address of the current owner
    /// @return owner_ Address of the current owner
    function owner() external view override returns (address owner_) {
        owner_ = LibDiamond.contractOwner();
    }

}
