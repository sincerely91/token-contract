pragma solidity >=0.5.0 <0.6.0;

/// @dev The token controller contract must implement these functions
contract TokenController {
    /// @notice Notifies the controller about a token transfer allowing the
    ///  controller to react if desired
    /// @param _from The origin of the transfer
    /// @param _to The destination of the transfer
    /// @param _amount The amount of the transfer
    /// @return The adjusted transfer amount filtered by a specific token controller.
    function onTokenTransfer(address _from, address _to, uint _amount) public returns(uint);

    /// @notice Notifies the controller about an approval allowing the
    ///  controller to react if desired
    /// @param _owner The address that calls `approve()`
    /// @param _spender The spender in the `approve()` call
    /// @param _amount The amount in the `approve()` call
    /// @return The adjusted approve amount filtered by a specific token controller.
    function onTokenApprove(address _owner, address _spender, uint _amount) public returns(uint);
}




contract DSAuthority {
    function canCall(
        address src, address dst, bytes4 sig
    ) public view returns (bool);
}

contract DSAuthEvents {
    event LogSetAuthority (address indexed authority);
    event LogSetOwner     (address indexed owner);
}

contract DSAuth is DSAuthEvents {
    DSAuthority  public  authority;
    address      public  owner;

    constructor() public {
        owner = msg.sender;
        emit LogSetOwner(msg.sender);
    }

    function setOwner(address owner_)
        public
        auth
    {
        owner = owner_;
        emit LogSetOwner(owner);
    }

    function setAuthority(DSAuthority authority_)
        public
        auth
    {
        authority = authority_;
        emit LogSetAuthority(address(authority));
    }

    modifier auth {
        require(isAuthorized(msg.sender, msg.sig), "ds-auth-unauthorized");
        _;
    }

    function isAuthorized(address src, bytes4 sig) internal view returns (bool) {
        if (src == address(this)) {
            return true;
        } else if (src == owner) {
            return true;
        } else if (authority == DSAuthority(0)) {
            return false;
        } else {
            return authority.canCall(src, address(this), sig);
        }
    }
}



contract DSMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function min(uint x, uint y) internal pure returns (uint z) {
        return x <= y ? x : y;
    }
    function max(uint x, uint y) internal pure returns (uint z) {
        return x >= y ? x : y;
    }
    function imin(int x, int y) internal pure returns (int z) {
        return x <= y ? x : y;
    }
    function imax(int x, int y) internal pure returns (int z) {
        return x >= y ? x : y;
    }

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;

    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), RAY / 2) / RAY;
    }
    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, RAY), y / 2) / y;
    }

    // This famous algorithm is called "exponentiation by squaring"
    // and calculates x^n with x as fixed-point and n as regular unsigned.
    //
    // It's O(log n), instead of O(n) for naive repeated multiplication.
    //
    // These facts are why it works:
    //
    //  If n is even, then x^n = (x^2)^(n/2).
    //  If n is odd,  then x^n = x * x^(n-1),
    //   and applying the equation for even x gives
    //    x^n = x * (x^2)^((n-1) / 2).
    //
    //  Also, EVM division is flooring and
    //    floor[(n-1) / 2] = floor[n / 2].
    //
    function rpow(uint x, uint n) internal pure returns (uint z) {
        z = n % 2 != 0 ? x : RAY;

        for (n /= 2; n != 0; n /= 2) {
            x = rmul(x, x);

            if (n % 2 != 0) {
                z = rmul(z, x);
            }
        }
    }
}



contract LockdropController is TokenController, DSAuth, DSMath {
    uint public perNodeLockedAmount = 0;
    uint private lockedSupply = 0;
    mapping (address => bool) public lockdropList;
    
    event UpdatePerNodeLockedAmount(uint oldAmount, uint newAmount);
    event Lock(address indexed node);
    event Release(address indexed node);
    
    function setPerNodeLockedAmount(uint amount) public auth {
        require(amount != perNodeLockedAmount);
        emit UpdatePerNodeLockedAmount(perNodeLockedAmount, amount);
        perNodeLockedAmount = amount;
    }
    
    function lock(address node) public auth {
        lockdropList[node] = true;
        lockedSupply = add(lockedSupply, perNodeLockedAmount);
        emit Lock(node);
    }
    
    function release(address node) public auth {
        delete lockdropList[node];
        lockedSupply = sub(lockedSupply, perNodeLockedAmount);
        emit Release(node);
    }
    
    /// @notice For address in lockdropList it's only allowed to transfer the amount greater than the perNodeLockedAmount.
    function onTokenTransfer(address _from, address _to, uint _amount) public returns(uint) {
        if (!lockdropList[_from]) {
            return _amount;
        } else if (_amount <= perNodeLockedAmount) {
            return 0;
        } else {
            return (_amount - perNodeLockedAmount);
        }
    }
    
    /// @notice For address in lockdropList it's only allowed to approve the amount greater than the perNodeLockedAmount.
    function onTokenApprove(address _owner, address _spender, uint _amount) public returns(uint) {
        if (!lockdropList[_owner]) {
            return _amount;
        } else if (_amount <= perNodeLockedAmount) {
            return 0;
        } else {
            return (_amount - perNodeLockedAmount);
        }
    }
}