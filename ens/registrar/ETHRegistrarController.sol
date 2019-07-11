pragma solidity ^0.5.0;

import "./BaseRegistrarImplementation.sol";
import "./utils/StringUtils.sol";
import "../../utils/Owned.sol";
import "../../pi/pibc.sol";
import "../../utils/safeMath.sol";

/**
 * @dev A registrar controller for registering and renewing names at fixed cost.
 */
contract ETHRegistrarController is Owned {
    using StringUtils for *;
    using SafeMath for uint;

    uint constant public MIN_REGISTRATION_DURATION = 28 days;

    bytes4 constant private INTERFACE_META_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 constant private COMMITMENT_CONTROLLER_ID = bytes4(
        keccak256("rentPrice(string,uint256)") ^
        keccak256("available(string)") ^
        keccak256("makeCommitment(string,address,bytes32)") ^
        keccak256("commit(bytes32)") ^
        keccak256("register(string,address,uint256,bytes32)") ^
        keccak256("renew(string,uint256)")
    );

    PIBC pitoken;
    BaseRegistrarImplementation base;
    uint public minCommitmentAge;
    uint public maxCommitmentAge;

    mapping(bytes32=>uint) public commitments;
    mapping(address => uint) lockedBalance;
    mapping(address => uint) recentPayment;

    event NameRegistered(string name, bytes32 indexed label, address indexed owner, uint cost, uint expires);
    event NameRenewed(string name, bytes32 indexed label, uint cost, uint expires);
    event NewPriceOracle(address indexed oracle);

    constructor(PIBC _pitoken, BaseRegistrarImplementation _base, uint _minCommitmentAge, uint _maxCommitmentAge) public {
        require(_maxCommitmentAge > _minCommitmentAge);

        pitoken = _pitoken;
        base = _base;
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
    }

    function rentPrice(string memory name, uint duration) view public returns(uint) {
        bytes32 hash = keccak256(bytes(name));
        //cambiar esta logica!!!!!!!!!!!!!!
        uint price = 500000;
        return price;
    }

    function valid(string memory name) public pure returns(bool) {
        return name.strlen() > 6;
    }

    function available(string memory name) public view returns(bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(uint256(label));
    }

    function makeCommitment(string memory name, address owner, bytes32 secret) pure public returns(bytes32) {
        bytes32 label = keccak256(bytes(name));
        return keccak256(abi.encodePacked(label, owner, secret));
    }

    function commit(bytes32 commitment) public {
        require(commitments[commitment] + maxCommitmentAge < now);
        commitments[commitment] = now;
    }

    function register(string calldata name, address owner, uint duration, bytes32 secret) external payable {
        // Require a valid commitment
        bytes32 commitment = makeCommitment(name, owner, secret);
        require(commitments[commitment] + minCommitmentAge <= now, "bad commitment");

        // If the commitment is too old, or the name is registered, stop
        require(commitments[commitment] + maxCommitmentAge > now, "commitment too old");
        require(available(name), "not available name");

        delete(commitments[commitment]);

        uint cost = rentPrice(name, duration);
        require(duration >= MIN_REGISTRATION_DURATION, "bad duration");
		pitoken.charge(address(this), cost);

        bytes32 label = keccak256(bytes(name));
        uint expires = base.register(uint256(label), owner, duration);
        emit NameRegistered(name, label, owner, cost, expires);
    }

    function renew(string calldata name, uint duration) external payable {
        uint cost = rentPrice(name, duration);
		pitoken.charge(address(this), cost);

        bytes32 label = keccak256(bytes(name));
        uint expires = base.renew(uint256(label), duration);

        emit NameRenewed(name, label, cost, expires);
    }

    function setCommitmentAges(uint _minCommitmentAge, uint _maxCommitmentAge) public onlyOwner {
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
    }

    function withdraw() public onlyOwner {
        uint controller_balance = pitoken.balanceOf(address(this));
		pitoken.transfer(msg.sender, controller_balance.mul(9999).div(10000));
    }

    function supportsInterface(bytes4 interfaceID) external pure returns (bool) {
        return interfaceID == INTERFACE_META_ID ||
               interfaceID == COMMITMENT_CONTROLLER_ID;
    }
    
    function tokenFallback(address _from, uint _value) public {
	    require(msg.sender == address(pitoken));
	    require(_value >= 0);
	}

}
