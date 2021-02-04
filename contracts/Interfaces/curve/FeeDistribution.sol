// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;

interface FeeDistribution {
    function claim(address) external returns (uint);
}