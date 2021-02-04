// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./interfaces/yearn/Proxy.sol";
import "./interfaces/curve/IMinter.sol";
import "./interfaces/curve/FeeDistribution.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StrategyProxy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    Proxy public constant proxy = Proxy(0xF147b8125d2ef93FB6965Db97D6746952a133934);
    address public constant mintr = address(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);
    address public constant crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant gauge = address(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB);
    address public constant y = address(0xFA712EE4788C042e2B7BB55E6cb8ec569C4530c1);
    address public constant yveCRV = address(0xc5bDdf9843308380375a611c18B50Fb9341f502A);
    address public constant CRV3 = address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    FeeDistribution public constant feeDistribution = FeeDistribution(0xA464e6DCda8AC41e03616F95f4BC98a13b8922Dc);

    mapping(address => bool) public strategies;
    address public governance;

    constructor() public {
        governance = msg.sender;
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function approveStrategy(address _strategy) external {
        require(msg.sender == governance, "!governance");
        strategies[_strategy] = true;
    }

    function revokeStrategy(address _strategy) external {
        require(msg.sender == governance || msg.sender == _strategy, "!governance");
        strategies[_strategy] = false;
    }

    function lock() external {
        uint256 amount = IERC20(crv).balanceOf(address(proxy));
        if (amount > 0) proxy.increaseAmount(amount);
    }

    function vote(address _gauge, uint256 _amount) public {
        require(strategies[msg.sender], "!strategy");
        proxy.execute(gauge, 0, abi.encodeWithSignature("vote_for_gauge_weights(address,uint256)", _gauge, _amount));
    }

    function withdraw(address _gauge, address _token, uint256 _amount) public returns (uint256) {
        require(strategies[msg.sender], "!strategy");
        uint256 _before = IERC20(_token).balanceOf(address(proxy));
        proxy.execute(_gauge, 0, abi.encodeWithSignature("withdraw(uint256)", _amount));
        uint256 _after = IERC20(_token).balanceOf(address(proxy));
        uint256 _net = _after.sub(_before);
        proxy.execute(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _net));
        return _net;
    }

    function balanceOf(address _gauge) public view returns (uint256) {
        return IERC20(_gauge).balanceOf(address(proxy));
    }

    // function balanceOfRewards(address _gauge, address _rewardToken) external view returns (uint256){
    //     // .execute signature -->
    //     // address to, uint value, bytes calldata data)
    //     (bool success, bytes memory i) = proxy.execute(_gauge, 0, abi.encodeWithSignature("reward_integral(address)", _rewardToken));
    //     uint256 integral = bytesToUint(i);
    //     (success, i) = proxy.execute(_gauge, 0, abi.encodeWithSignature("reward_integral_for(address,address)", _rewardToken, msg.sender));
    //     uint256 integral_for = bytesToUint(i);
    //     uint256 user_balance = IERC20(_gauge).balanceOf(address(proxy));
    //     return user_balance * (integral - integral_for) / 1e18;
    // }

    function withdrawAll(address _gauge, address _token) external returns (uint256) {
        require(strategies[msg.sender], "!strategy");
        return withdraw(_gauge, _token, balanceOf(_gauge));
    }

    function deposit(address _gauge, address _token) external {
        require(strategies[msg.sender], "!strategy");
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(address(proxy), _balance);
        _balance = IERC20(_token).balanceOf(address(proxy));

        proxy.execute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _gauge, 0));
        proxy.execute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _gauge, _balance));
        (bool success, ) = proxy.execute(_gauge, 0, abi.encodeWithSignature("deposit(uint256)", _balance));
        if (!success) assert(false);
    }

    function harvest(address _gauge) external {
        require(strategies[msg.sender], "!strategy");
        uint256 _before = IERC20(crv).balanceOf(address(proxy)); // There may already be a CRV balance. Harvest should exclude this.
        proxy.execute(mintr, 0, abi.encodeWithSignature("mint(address)", _gauge));
        uint256 _after = IERC20(crv).balanceOf(address(proxy));
        uint256 _balance = _after.sub(_before);
        proxy.execute(crv, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _balance));
    }

    function harvestWithTokens(address _gauge, address[] memory rewardsTokens) external {
        require(strategies[msg.sender], "!strategy");
        uint256 _before = IERC20(crv).balanceOf(address(proxy)); // There may already be a CRV balance. Harvest should exclude this.
        proxy.execute(mintr, 0, abi.encodeWithSignature("mint(address)", _gauge));
        (bool successful,) = proxy.execute(_gauge, 0, abi.encodeWithSignature("claim_rewards()"));
        if(!successful){revert();}
        uint256 _after = IERC20(crv).balanceOf(address(proxy));
        uint256 _balance = _after.sub(_before);
        proxy.execute(crv, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _balance));
        for(uint i=0; i<rewardsTokens.length; i++){
            uint256 rewardsBalance = IERC20(rewardsTokens[i]).balanceOf(address(proxy));
            (bool success,) = proxy.execute(rewardsTokens[i], 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, rewardsBalance));
            if(!success){revert();}
        }
    }

    function claim(address recipient) external {
        require(msg.sender == yveCRV, "!strategy");
        uint amount = feeDistribution.claim(address(proxy));
        if (amount > 0) {
            proxy.execute(CRV3, 0, abi.encodeWithSignature("transfer(address,uint256)", recipient, amount));
        }
    }

    function bytesToUint(bytes memory b) internal returns (uint256){
        uint256 number;
        for(uint i=0;i<b.length;i++){
            number = number + uint(uint8(b[i]))*(2**(8*(b.length-(i+1))));
        }
        return number;
    }
}