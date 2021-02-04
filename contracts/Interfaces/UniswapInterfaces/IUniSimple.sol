// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.6.2;

interface IUniSimple {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}