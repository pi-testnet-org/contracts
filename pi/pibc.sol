pragma solidity 0.5.0;

import './IRC223.sol';
import './IERC20.sol';
import './ERC223_receiving_contract.sol';
import "../utils/safeMath.sol";

/**
 * @title Reference implementation of the ERC223 standard token.
 */
contract PIBC is IRC223, IERC20 {
    using SafeMath for uint;
    
    mapping(address => uint) public balances; // List of user balances.
    mapping(address => mapping (address => uint)) public approved;
    mapping(address => mapping (address => uint)) public ttl;
    mapping(address => bool) public chargers;
    string private _name;
    string private _symbol;
    uint8 _decimals;
    uint public commisionRate;
    address private _owner;
    address private _commisioner; //0x4E911d2D6B83e4746055ccb167596bF9f2e680d2
    event Commision(uint256 commision);
    uint private _ttlLimit;
    
    constructor(address commisioner, address owner) public{
        _name = "Pi token";
        _symbol = "PIT";
        _decimals = 5;
        totalSupply = 10000000000000000000;
        balances[owner] = totalSupply;
        _owner = owner;
        _commisioner = commisioner;
        commisionRate = 10000;
        _ttlLimit = 360;
    }
    
    modifier onlyChargers {
        require(chargers[msg.sender]);
        _;
    }
    
    function name() public view returns (string memory){
        return _name;
    }
    function symbol() public view returns (string memory){
        return _symbol;
    }
    function decimals() public view returns (uint8){
        return _decimals;
    }
    
    function _transfer(address _to, address _from, uint _value) internal{
        require(balances[_from] >= _value, "No balance");
        uint codeLength;
        uint256 commision;
        bytes memory empty;

        assembly {
            // Retrieve the size of the code on target address, this needs assembly .
            codeLength := extcodesize(_to)
        }

        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_value);
        commision = _value.div(commisionRate);
        balances[_from] = balances[_from].sub(commision);
        balances[_commisioner] = balances[_commisioner].add(commision);
        if(codeLength>0) {
            ERC223ReceivingContract receiver = ERC223ReceivingContract(_to);
            receiver.tokenFallback(_from, _value);
        }
        emit Transfer(_from, _to, _value);
        emit Transfer(_from, _to, _value, empty);
        emit Commision(commision);
    }
    
    function transfer(address _to, uint _value) public {
        _transfer(_to, msg.sender,_value);
    }
    
    function transferFrom (address _to, address _from) public {
        require(approved[_from][_to] > 0, "a");
        //require(ttl[msg.sender][_to] > block.number, "b");
        uint _value = approved[_from][_to];
        ttl[msg.sender][_to] = 0;
        approved[_from][_to] = 0;
        _transfer(_to, _from, _value);
        
    }
    
    function approve (address _to, uint _value) public{
        require(_value <= balances[msg.sender]);
        approved[msg.sender][_to] = approved[msg.sender][_to].add(_value);
        ttl[msg.sender][_to] = block.number.add(_ttlLimit);

    }
    
    function disapprove (address _spender) public {
        approved[msg.sender][_spender] = 0;
    }
    
    function allowance(address owner, address spender) external view returns (uint) {
        return approved[owner][spender];
    }

    function balanceOf(address _user) public view returns (uint balance) {
        return balances[_user];
    }
    
    function setTtl(uint ttlLimit) public {
        require(msg.sender == _owner);
        _ttlLimit = ttlLimit;
    }
    
    function setCommisionRate (uint _commisionRate) public {
        require(msg.sender == _owner);
        commisionRate = _commisionRate;
    }
    
    function setCommisioner (address commisioner) public {
        require(msg.sender == _owner);
        _commisioner = commisioner;
    }
    
    function setCharger (address _newCharger) public {
        require(msg.sender == _owner);
        chargers[_newCharger] = true;
    }
    
    function charge (address _to, uint _value) public onlyChargers {
        _transfer(_to, tx.origin, _value);
    }
}
