// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./interfaces/curve/Curve.sol";
import "./interfaces/curve/Gauge.sol";
import "./interfaces/yearn/IStrategyProxy.sol";
import "./interfaces/curve/IMinter.sol";
import "./interfaces/curve/ICrvV3.sol";
import "./interfaces/lido/ISteth.sol";
import "./interfaces/1inch/IMooniswap.sol";
import "./interfaces/UniswapInterfaces/IUniswapV2Router02.sol";


// These are the core Yearn libraries
import {
    BaseStrategy
} from "@yearnvaults/contracts/BaseStrategy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";


// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address private uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private sushiswapRouter = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address private mooniswappool = 0x1f629794B34FFb3B29FF206Be5478A52678b47ae;

    address public ldoRouter = 0x1f629794B34FFb3B29FF206Be5478A52678b47ae;
    address[] public ldoPath;

    address public crvRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address[] public crvPath;

    address public constant gauge = address(0x182B723a58739a9c974cFDB385ceaDb237453c28);
    Gauge public LiquidityGaugeV2 =  Gauge(address(0x182B723a58739a9c974cFDB385ceaDb237453c28));
    ICurveFi public StableSwapSTETH =  ICurveFi(address(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022));
   // IMinter public CrvMinter = IMinter(address(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0));

    address public constant weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ISteth public stETH =  ISteth(address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84));
    IERC20 public LDO =  IERC20(address(0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32));
    ICrvV3 public CRV =  ICrvV3(address(0xD533a949740bb3306d119CC777fa900bA034cd52));
    IStrategyProxy public proxy;
    mapping (address => uint256) public rewardsBalance;
    address[] rewardsTokens;

    


    constructor(address _vault) public BaseStrategy(_vault) {
        // You can set these parameters on deployment to whatever you want
        maxReportDelay = 43200;
        profitFactor = 2000;
        debtThreshold = 400*1e18;

        want.safeApprove(address(LiquidityGaugeV2), uint256(-1));
        stETH.approve(address(StableSwapSTETH), uint256(-1));
        LDO.safeApprove(ldoRouter, uint256(-1));
        CRV.approve(crvRouter, uint256(-1));

        rewardsTokens.push(address(0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32));
        
        ldoPath = new address[](2);
        ldoPath[0] = address(LDO);
        ldoPath[1] = weth;

        crvPath = new address[](2);
        crvPath[0] = address(CRV);
        crvPath[1] = weth;
    }


    //we get eth
    receive() external payable {}


    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************
    //0 uniswap, 1 sushi, 2 inch
    function setLDORouter(uint256 exchange, address[] calldata _path) public onlyGovernance {
        if(exchange == 0){
            ldoRouter = uniswapRouter;
        }else if (exchange == 1) {
            ldoRouter = sushiswapRouter;
        }else if (exchange == 2) {
            ldoRouter = mooniswappool;
        }else{
            require(false, "incorrect pool");
        }

        ldoPath = _path;
        LDO.safeApprove(ldoRouter, uint256(-1));
    }

    function updateMooniswapPoolAddress(address newAddress) public onlyGovernance {
        mooniswappool = newAddress;
    }

    function setCRVRouter(uint256 exchange, address[] calldata _path) public onlyGovernance {
        if(exchange == 0){
            crvRouter = uniswapRouter;
        }else if (exchange == 1) {
            crvRouter = sushiswapRouter;
        }else{
            require(false, "incorrect pool");
        }
        crvPath = _path;
        CRV.approve(crvRouter, uint256(-1));
    }

    function setProxy(address _proxy) public onlyGovernance {
        proxy = IStrategyProxy(_proxy);
    }

    function name() external override view returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "StrategystETHCurve";
    }

    function estimatedTotalAssets() public override view returns (uint256) {
        return proxy.balanceOf(gauge);
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // TODO: Do stuff here to free up any returns back into `want`
        // NOTE: Return `_profit` which is value generated by all positions, priced in `want`
        // NOTE: Should try to free up at least `_debtOutstanding` of underlying position


        // TODO: 
        // 1. Check CRV balance
        // 2. Check LDO balance
        uint256 crvBalance = proxy.balanceOf(gauge);
        if(crvBalance > 0){    

            proxy.harvestWithTokens(gauge, rewardsTokens);
            // Get rewards balance
            for(uint i=0; i<rewardsTokens.length; i++) {
                rewardsBalance[rewardsTokens[i]] = IERC20(address(rewardsTokens[i])).balanceOf(address(this));
            }

            // Sell rewards
            for(uint i=0; i<rewardsTokens.length; i++) {
                if(rewardsBalance[rewardsTokens[i]] > 0){
                    _sell(address(rewardsTokens[i]), rewardsBalance[rewardsTokens[i]]);
                }
            }

            uint256 crv_balance = CRV.balanceOf(address(this));

            if(crv_balance > 0){
                _sell(address(CRV), crv_balance);
            }

            uint256 balance = address(this).balance;
            uint256 balance2 = stETH.balanceOf(address(this));

            if(balance > 0 || balance2 > 0){
                StableSwapSTETH.add_liquidity{value: balance}([balance, balance2], 0);
            }


            _profit = want.balanceOf(address(this));
        }

        if(_debtOutstanding > 0){
            if(_debtOutstanding > _profit){
                uint256 stakedBal = proxy.balanceOf(gauge);
                proxy.withdraw(gauge, address(want), Math.min(stakedBal,_debtOutstanding - _profit));
            }

            _debtPayment = Math.min(_debtOutstanding, want.balanceOf(address(this)).sub(_profit));
        }

        return (_profit, _loss, _debtPayment);
        
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 wantBalance = IERC20(want).balanceOf(address(this));
        if(wantBalance > 0){
            IERC20(want).safeTransfer(address(proxy), wantBalance);
            IStrategyProxy(proxy).deposit(gauge, address(want));
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {

        uint256 wantBal = want.balanceOf(address(this));
        uint256 stakedBal = proxy.balanceOf(gauge);

        if(_amountNeeded > wantBal){
            proxy.withdraw(gauge, address(want), _amountNeeded - wantBal);
        }

        _liquidatedAmount = Math.min(_amountNeeded, want.balanceOf(address(this)));

    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary
    // Now that we're connected to the voter/strategyProxy, we can simply revoke the old strategy. Governance will need to set
    function prepareMigration(address _newStrategy) internal override {
        proxy.revokeStrategy(address(this));
    }

    //sell all function
    function _sell(address currency, uint256 amount) internal {

        if(currency == address(LDO)){
            if(ldoRouter == mooniswappool){
                //we sell to stETH
                IMooniswap(mooniswappool).swap(currency, address(stETH), amount, 1, strategist);
            }else{
                IUniswapV2Router02(ldoRouter).swapExactTokensForETH(amount, uint256(0), ldoPath, address(this), now);
            }
            
        }
        else if(currency == address(CRV)){
            IUniswapV2Router02(crvRouter).swapExactTokensForETH(amount, uint256(0), crvPath, address(this), now);
        }else{
            require(false, "BAD SELL");
        }

    }


    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }
    function protectedTokens()
        internal
        override
        view
        returns (address[] memory)
    {

        address[] memory protected = new address[](1);
          protected[0] = address(LiquidityGaugeV2);
          return protected;
    }
}
