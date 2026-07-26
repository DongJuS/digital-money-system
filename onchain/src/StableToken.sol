// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title StableToken
/// @notice An institution-issued digital currency (no collateral held).
///         The `issuer` (e.g. a central-bank-like institution) mints and distributes
///         coins to holders; holders transfer freely. A minimal, self-contained ERC-20.
contract StableToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    /// @notice The institution authorized to issue (mint) and retire (burn) coins.
    address public issuer;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Issued(address indexed to, uint256 value);
    event Retired(address indexed from, uint256 value);
    event IssuerTransferred(address indexed from, address indexed to);

    modifier onlyIssuer() {
        require(msg.sender == issuer, "StableToken: not issuer");
        _;
    }

    constructor(string memory _name, string memory _symbol, address _issuer) {
        require(_issuer != address(0), "StableToken: zero issuer");
        name = _name;
        symbol = _symbol;
        issuer = _issuer;
        emit IssuerTransferred(address(0), _issuer);
    }

    // --- ERC-20 ---

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "StableToken: allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "StableToken: zero to");
        uint256 bal = balanceOf[from];
        require(bal >= value, "StableToken: balance");
        unchecked {
            balanceOf[from] = bal - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }

    // --- Institution controls ---

    /// @notice Issue new coins to a holder (institution only).
    function issue(address to, uint256 value) external onlyIssuer {
        require(to != address(0), "StableToken: zero to");
        totalSupply += value;
        unchecked {
            balanceOf[to] += value;
        }
        emit Issued(to, value);
        emit Transfer(address(0), to, value);
    }

    /// @notice Issue to many holders at once (payroll / airdrop style).
    function issueBatch(address[] calldata to, uint256[] calldata value) external onlyIssuer {
        require(to.length == value.length, "StableToken: length");
        for (uint256 i = 0; i < to.length; i++) {
            require(to[i] != address(0), "StableToken: zero to");
            totalSupply += value[i];
            unchecked {
                balanceOf[to[i]] += value[i];
            }
            emit Issued(to[i], value[i]);
            emit Transfer(address(0), to[i], value[i]);
        }
    }

    /// @notice Retire coins from circulation (institution only).
    function retire(address from, uint256 value) external onlyIssuer {
        uint256 bal = balanceOf[from];
        require(bal >= value, "StableToken: balance");
        unchecked {
            balanceOf[from] = bal - value;
            totalSupply -= value;
        }
        emit Retired(from, value);
        emit Transfer(from, address(0), value);
    }

    function transferIssuer(address to) external onlyIssuer {
        require(to != address(0), "StableToken: zero to");
        emit IssuerTransferred(issuer, to);
        issuer = to;
    }
}
