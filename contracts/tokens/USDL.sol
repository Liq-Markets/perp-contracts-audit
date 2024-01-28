// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../core/interfaces/IFeeSharing.sol";
import "./interfaces/IUSDL.sol";
import "./YieldToken.sol";

contract USDL is YieldToken, IUSDL {

    mapping (address => bool) public vaults;

    modifier onlyVault() {
        require(vaults[msg.sender], "USDL: forbidden");
        _;
    }

    constructor(address _vault) public YieldToken("USD Liq", "USDL", 0) {
        vaults[_vault] = true;
        IFeeSharing feeSharing = IFeeSharing(0x8680CEaBcb9b56913c519c069Add6Bc3494B7020); // This address is the address of the SFS contract
        feeSharing.assign(84); //Registers this contract and assigns the NFT to the owner of this contract
    }

    function addVault(address _vault) external override onlyGov {
        vaults[_vault] = true;
    }

    function removeVault(address _vault) external override onlyGov {
        vaults[_vault] = false;
    }

    function mint(address _account, uint256 _amount) external override onlyVault {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override onlyVault {
        _burn(_account, _amount);
    }
}
