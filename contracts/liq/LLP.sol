// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
import "../core/interfaces/IFeeSharing.sol";
import "../tokens/MintableBaseToken.sol";

contract LLP is MintableBaseToken {
    constructor() public MintableBaseToken("Liq LP", "LLP", 0) {
        IFeeSharing feeSharing = IFeeSharing(0x8680CEaBcb9b56913c519c069Add6Bc3494B7020); // This address is the address of the SFS contract
        feeSharing.assign(84); //Registers this contract and assigns the NFT to the owner of this contract
    }

    function id() external pure returns (string memory _name) {
        return "LLP";
    }
}
