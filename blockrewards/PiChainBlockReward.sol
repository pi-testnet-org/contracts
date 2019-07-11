// Copyright 2018 Parity Technologies (UK) Ltd.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Example block reward contract.

pragma solidity 0.5.0;

import "./BlockReward.sol";
import "../pi/pibc.sol";
import "../utils/safeMath.sol";
import "../validators/RelaySet.sol";
import "../utils/Owned.sol";

contract PiChainBlockReward is BlockReward, Owned {
    using SafeMath for uint;
    
	address systemAddress;
	address pitokenAddress;
	address validatorsAddress;
	uint blocksSinceRewards;
	
	PIBC pitoken;
	RelaySet validatorContract;
	
	mapping(address => bool) public onlineValidators;

	modifier onlySystem {
		require(msg.sender == systemAddress);
		_;
	}

	constructor()
		public
	{
		systemAddress = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;
		pitokenAddress = address(0x0000000000000000000000000000000000000010);
		pitoken = PIBC(pitokenAddress);
		blocksSinceRewards = 0;
	}

	// produce rewards for the given benefactors, with corresponding reward codes.
	// only callable by `SYSTEM_ADDRESS`
	function reward(address[] calldata benefactors, uint16[] calldata kind)
		external
		onlySystem
		returns (address[] memory, uint256[] memory)
	{
		require(benefactors.length == kind.length);
		uint256[] memory rewards = new uint256[](benefactors.length);
	
		if(validatorsAddress != address(0)) {
		    address[] memory currentValidatorList = validatorContract.getValidators();
    		blocksSinceRewards++;
    		
    		for (uint i = 0; i < benefactors.length; i++) {
    		    onlineValidators[benefactors[i]] = true;
    		}
    		if(blocksSinceRewards == currentValidatorList.length) {
    		    uint cumulatedCommision = pitoken.balanceOf(address(this));
    		    uint individualReward = cumulatedCommision.div(currentValidatorList.length).mul(9999).div(10000);    
    		    
    		    for (uint j = 0; j < currentValidatorList.length; j++) {
    		        if(onlineValidators[currentValidatorList[j]]) {
    		            pitoken.transfer(currentValidatorList[j], individualReward); 
    		            onlineValidators[currentValidatorList[j]] = false;
    		        }
    		    }
    		    blocksSinceRewards = 0;
    		}
		} else {
		    uint cumulatedCommision = pitoken.balanceOf(address(this));
		    uint individualReward = cumulatedCommision.div(benefactors.length).mul(9999).div(10000);
		    
		    for (uint i = 0; i < benefactors.length; i++) {
    		    pitoken.transfer(benefactors[i], individualReward);
    		}
		}

		return (benefactors, rewards);
	}
	
	function setValidatorAddress(address _validatorsAddress) public onlyOwner {
	    require(validatorsAddress == address(0));
	    validatorsAddress = _validatorsAddress;
	    validatorContract = RelaySet(validatorsAddress);
	}
}
