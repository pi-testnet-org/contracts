// Copyright 2018, Parity Technologies Ltd.
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

// An owned validator set contract where the owner can add or remove validators.
// This is an abstract contract that provides the base logic for adding/removing
// validators and provides base implementations for the `ValidatorSet`
// interface. The base implementations of the misbehavior reporting functions
// perform validation on the reported and reporter validators according to the
// currently active validator set. The base implementation of `finalizeChange`
// validates that there are existing unfinalized changes.

pragma solidity 0.5.0;

import "../../utils/Owned.sol";
import "../../pi/pibc.sol";
import "../../utils/safeMath.sol";


contract BaseOwnedSet is Owned {
    using SafeMath for uint;
    
	// EVENTS
	event ChangeFinalized(address[] currentSet);

	// STATE

	// Was the last validator change finalized. Implies validators == pending
	bool public finalized;

	// TYPES
	struct AddressStatus {
		bool isIn;
		uint index;
	}

	// EVENTS
	event Report(address indexed reporter, address indexed reported, bool indexed malicious);

	// STATE
	uint public recentBlocks = 20;

	// Current list of addresses entitled to participate in the consensus.
	address[] validators;
	address[] pending;
	mapping(address => AddressStatus) status;
	mapping(address => uint) public lockedBalance;
	mapping(address => address[]) public acceptedBy;
	
	uint public currentValidatorPrice;
	uint public stepValidatorPrice;
	uint public sellValidatorPrice;
	PIBC pitoken;
	address mainWallet;

	// MODIFIERS

	/// Asserts whether a given address is currently a validator. A validator
	/// that is pending to be added is not considered a validator, only when
	/// that change is finalized will this method return true. A validator that
	/// is pending to be removed is immediately not considered a validator
	/// (before the change is finalized).
	///
	/// For the purposes of this contract one of the consequences is that you
	/// can't report on a validator that is currently active but pending to be
	/// removed. This is a compromise for simplicity since the reporting
	/// functions only emit events which can be tracked off-chain.
	modifier isValidator(address _someone) {
		bool isIn = status[_someone].isIn;
		uint index = status[_someone].index;

		require(isIn && index < validators.length && validators[index] == _someone);
		_;
	}

	modifier isNotValidator(address _someone) {
		require(!status[_someone].isIn);
		_;
	}

	modifier isRecent(uint _blockNumber) {
		require(block.number <= _blockNumber + recentBlocks && _blockNumber < block.number);
		_;
	}

	modifier whenFinalized() {
		require(finalized);
		_;
	}

	modifier whenNotFinalized() {
		require(!finalized);
		_;
	}

	constructor(address[] memory _initial)
		public
	{
		pending = _initial;
		for (uint i = 0; i < _initial.length; i++) {
			status[_initial[i]].isIn = true;
			status[_initial[i]].index = i;
		}
		validators = pending;
		stepValidatorPrice = 100000000;
		sellValidatorPrice = (validators.length.sub(1)).mul(stepValidatorPrice);
	    currentValidatorPrice = (validators.length.add(1)).mul(stepValidatorPrice);
		pitoken = PIBC(address(0x0000000000000000000000000000000000000010));
		mainWallet = address(0xf6bD003d07eBA2027C34fACE6af863Fd3f8B5a14);
	}

	// OWNER FUNCTIONS

	// Add a validator.
	function addValidator(address _validator)
		internal
		isNotValidator(_validator)
	{
		status[_validator].isIn = true;
		status[_validator].index = pending.length;
		pending.push(_validator);
		pitoken.transferFrom(address(this), _validator);
		require(lockedBalance[_validator] == currentValidatorPrice);
		triggerChange();
	}
	
	function acceptValidator(address _validator) 
	external 
	isNotValidator(_validator) 
	isValidator(msg.sender)
	{
	    acceptedBy[_validator].push(msg.sender);
	    if (acceptedBy[_validator].length > validators.length.div(2)) {
	        addValidator(_validator);
	    }
	}

	// Remove a validator.
	function removeValidator()
		external
		isValidator(msg.sender)
	{
		// Remove validator from pending by moving the
		// last element to its slot
		uint index = status[msg.sender].index;
		pending[index] = pending[pending.length - 1];
		status[pending[index]].index = index;
		delete pending[pending.length - 1];
		pending.length--;

		// Reset address status
		delete status[msg.sender];
		
		pitoken.transfer(msg.sender, sellValidatorPrice.mul(9999).div(10000));
		pitoken.transfer(mainWallet, stepValidatorPrice.mul(9999).div(10000));
		lockedBalance[msg.sender] = 0;

		triggerChange();
	}

	function setRecentBlocks(uint _recentBlocks)
		external
		onlyOwner
	{
		recentBlocks = _recentBlocks;
	}

	// GETTERS

	// Called to determine the current set of validators.
	function getValidators()
		external
		view
		returns (address[] memory)
	{
		return validators;
	}

	// Called to determine the pending set of validators.
	function getPending()
		external
		view
		returns (address[] memory)
	{
		return pending;
	}

	// INTERNAL

	// Report that a validator has misbehaved in a benign way.
	function baseReportBenign(address _reporter, address _validator, uint _blockNumber)
		internal
		isValidator(_reporter)
		isValidator(_validator)
		isRecent(_blockNumber)
	{
		emit Report(_reporter, _validator, false);
	}

	// Report that a validator has misbehaved maliciously.
	function baseReportMalicious(
		address _reporter,
		address _validator,
		uint _blockNumber,
		bytes memory _proof
	)
		internal
		isValidator(_reporter)
		isValidator(_validator)
		isRecent(_blockNumber)
	{
		emit Report(_reporter, _validator, true);
	}

	// Called when an initiated change reaches finality and is activated.
	function baseFinalizeChange()
		internal
		whenNotFinalized
	{
		validators = pending;
		finalized = true;
		updateValidatorPrice();
		emit ChangeFinalized(validators);
	}
		
	function finalizeOfflineValidator(address _validator) external onlyOwner whenNotFinalized {
	    pending = validators;
	    status[_validator].isIn = false;
	    finalized = true;
	}

	// PRIVATE

	function triggerChange()
		private
		whenFinalized
	{
		finalized = false;
		initiateChange();
	}

	function initiateChange()
		private;
	
	function getLockedBalance(address _validator) public view returns(uint256) {
	    return lockedBalance[_validator];
	}
	
	function updateValidatorPrice() internal {
	    sellValidatorPrice = (validators.length.sub(1)).mul(stepValidatorPrice);
	    currentValidatorPrice = (validators.length.add(1)).mul(stepValidatorPrice);
	}
	
	function tokenFallback(address _from, uint _value) public {
	    require(msg.sender == address(pitoken));
	    require(_value == currentValidatorPrice);
	    lockedBalance[_from] = _value;
	}
}

