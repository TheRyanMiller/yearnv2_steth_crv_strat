// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;

interface IStrategyProxy {

    function setGovernance(address _governance) external;
    function approveStrategy(address _strategy) external;
    function revokeStrategy(address _strategy) external;
    function lock() external;
    function vote(address _gauge, uint256 _amount) external;
    function withdraw(address _gauge, address _token, uint256 _amount) external returns (uint256);
    function balanceOf(address _gauge) external view returns (uint256);
    function balanceOfRewards(address _gauge, address[] memory rewardTokens) external view returns (uint256);
    function withdrawAll(address _gauge, address _token) external;
    function deposit(address _gauge, address _token) external;
    function harvest(address _gauge) external;
    function harvestWithTokens(address _gauge, address[] memory rewardsTokens) external;
    function claim(address recipient) external;
}